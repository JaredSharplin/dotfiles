#!/usr/bin/env ruby
# frozen_string_literal: true

# personal-write-rules-check.rb — personal, cross-project PreToolUse hook on
# Edit / MultiEdit / Write / Bash.
#
# Reads stdin JSON from Claude Code and applies rules from
# ~/.claude/hooks/personal-write-rules.yml. Unlike payaus's project-scoped
# write-rules-check.rb, this hook is personal: it reads ONLY the fixed personal
# rules file (never a project's write-rules.yml), so it can run alongside a
# project's own dispatcher in the same session without either grabbing the
# other's rules. Sentinels for once-per-session rules live under a
# `personal-write-rules/` subdir so a personal rule can't collide with a
# project rule of the same name.
#
# Each rule:
#   type:              "block" (deny every matching tool call),
#                      "block_once" (deny the first matching call per session,
#                      then let subsequent calls through silently — useful to
#                      force reconsideration once without permanent friction),
#                      "warn" (inject context, never deny), or
#                      "warn_once" (inject context on the first matching call
#                      per session only).
#   files:             Globs (relative to CLAUDE_PROJECT_DIR, ** supported).
#                      Applies the rule to Edit/Write/MultiEdit calls. By
#                      default the rule also fires on Bash writes to the same
#                      paths (see bash_writes below).
#   pattern:           Optional Ruby regex matched against the new content.
#                      Omit to fire on file-glob match alone. When set, the
#                      Bash side is automatically disabled (content regexes
#                      have no meaningful Bash analog).
#   bash_writes:       Optional boolean. Defaults to true when `files:` is set
#                      and `pattern:` is not. Set to `false` to opt out — the
#                      rare case where you want to nudge Edit/Write but not
#                      shell writes. The script owns the verb taxonomy: shell
#                      redirects (`>`, `>>`), write-style commands (tee/cp/mv/
#                      install/dd), and in-place editors (sed -i / perl -i /
#                      awk -i). Globs in `files:` are converted to regex so
#                      patterns like `app/services/**/*` work on the Bash side.
#   bash_pattern:      Optional Ruby regex matched against the raw Bash
#                      command string (Bash tool only). Independent of
#                      `files:`/`bash_writes:` — use when the rule isn't about
#                      writing to a path but about a shell command shape.
#   context:           Static message returned to Claude.
#   context_script:    Optional path (relative to CLAUDE_PROJECT_DIR) to a
#                      script that emits the context dynamically. Receives
#                      CLAUDE_FILE_PATH, CLAUDE_RELATIVE_PATH, and
#                      CLAUDE_SESSION_ID via env. Stdout protocol:
#                        - Optional first line: "#sentinel-suffix:<value>"
#                          (suffix is appended to the per-session sentinel key,
#                          so a warn_once / block_once rule fires once per
#                          target rather than once for the whole session).
#                        - Remaining lines: the context body.
#                      Empty body suppresses the rule. Overrides static
#                      `context` when both are set.
#   opt_out_env:       Optional env var name. When set to any non-empty value,
#                      the rule is skipped. Kill switch from the shell.
#   opt_in_env:        Optional env var name. When unset or empty, the rule is
#                      skipped. Keeps a rule dormant unless explicitly enabled.
#
# block / block_once surface as hookSpecificOutput.permissionDecision = "deny"
# (with permissionDecisionReason). warn / warn_once surface as additionalContext.

require "fileutils"
require "json"
require "open3"
require "yaml"

BLOCK_ONCE_RETRY_HINT = "You may run this exact command again and it will not be blocked again this session."

ALLOWED_TYPES = ["block", "block_once", "warn", "warn_once"].freeze
ONCE_TYPES = ["block_once", "warn_once"].freeze

WRITE_FILE_VERBS = ["tee", "cp", "mv", "install", "dd"].freeze
WRITE_INPLACE_EDITORS = ["sed", "gsed", "perl", "awk", "gawk"].freeze

# Convert an fnmatch-style glob to a regex fragment matching the same paths.
# Supports `**/`, `**`, `*`, `?` plus literal segments. `*` does not cross `/`;
# `**/` matches zero-or-more path segments.
def glob_to_path_regex(glob)
  out = +""
  i = 0
  while i < glob.length
    if glob[i, 3] == "**/"
      out << '(?:[^\s|&]+/)*'
      i += 3
    elsif glob[i, 2] == "**"
      out << '[^\s|&]*'
      i += 2
    elsif glob[i] == "*"
      out << '[^/\s|&]*'
      i += 1
    elsif glob[i] == "?"
      out << '[^/\s|&]'
      i += 1
    else
      j = i
      j += 1 while j < glob.length && !["*", "?"].include?(glob[j])
      out << Regexp.escape(glob[i...j])
      i = j
    end
  end
  out
end

def derive_bash_write_regex(globs)
  return if globs.empty?

  alt = globs.map { |g| glob_to_path_regex(g) }.join("|")
  Regexp.new(
    [
      "(?:>>?\\s*['\"]?(?:#{alt})\\b)",
      "(?:\\b(?:#{WRITE_FILE_VERBS.join("|")})\\b[^\\n|;&]*\\b(?:#{alt})\\b)",
      "(?:\\b(?:#{WRITE_INPLACE_EDITORS.join("|")})\\b[^\\n|;&]*\\s-i\\b[^\\n|;&]*\\b(?:#{alt})\\b)"
    ].join("|")
  )
end

def bash_writes_enabled?(rule, globs, pattern)
  explicit = rule["bash_writes"]
  return explicit == true unless explicit.nil?

  !globs.empty? && pattern.to_s.empty?
end

def build_bash_regex(rule, globs, pattern)
  parts = []
  parts << derive_bash_write_regex(globs) if bash_writes_enabled?(rule, globs, pattern)
  bash_pattern = rule["bash_pattern"].to_s
  unless bash_pattern.empty?
    begin
      parts << Regexp.new(bash_pattern)
    rescue RegexpError
      warn("[personal-write-rules] invalid bash_pattern for rule: #{bash_pattern}")
    end
  end
  parts.compact!
  return if parts.empty?

  Regexp.union(*parts)
end

input = JSON.parse($stdin.read)
tool = input["tool_name"]
session_id = input["session_id"].to_s

bash_command = (tool == "Bash") ? input.dig("tool_input", "command").to_s : nil

file_path = input.dig("tool_input", "file_path").to_s
exit 0 if file_path.empty? && bash_command.nil?

new_content = case tool
when "Bash"   then nil
when "Edit"   then input.dig("tool_input", "new_string").to_s
when "MultiEdit"
  Array(input.dig("tool_input", "edits")).map { |edit| edit["new_string"].to_s }.join("\n")
when "Write" then input.dig("tool_input", "content").to_s
else exit(0)
end

# Personal hook: read ONLY the fixed personal rules file — never a project's
# write-rules.yml. This is what lets it coexist with a project dispatcher.
config_path = File.expand_path("~/.claude/hooks/personal-write-rules.yml")
exit 0 unless File.exist?(config_path)

rules = YAML.safe_load_file(config_path) || {}
exit 0 if rules.empty?

project_dir = ENV["CLAUDE_PROJECT_DIR"].to_s

relative_path = if !project_dir.empty? && file_path.start_with?("#{project_dir}/")
  file_path[(project_dir.length + 1)..]
else
  file_path
end

fnmatch_flags = File::FNM_PATHNAME | File::FNM_DOTMATCH

# Sentinels live under a `personal-write-rules/` subdir so a personal rule
# can't collide with a project rule of the same name. Fall back to ~/.claude
# when there's no project dir.
sentinel_base = project_dir.empty? ? File.expand_path("~/.claude") : project_dir
session_dir = File.join(
  sentinel_base,
  "tmp",
  ".claude-advisory",
  "personal-write-rules",
  session_id.empty? ? "unknown-session" : session_id
)

blocks = []
warns = []
sentinels_to_touch = []

rules.each do |name, rule|
  next unless rule.is_a?(Hash)

  type = rule["type"]
  pattern = rule["pattern"]
  static_context = rule["context"].to_s
  context_script = rule["context_script"].to_s
  globs = Array(rule["files"])
  opt_out_env = rule["opt_out_env"].to_s
  opt_in_env = rule["opt_in_env"].to_s

  next unless ALLOWED_TYPES.include?(type)
  next if static_context.empty? && context_script.empty?
  next if !opt_out_env.empty? && !ENV[opt_out_env].to_s.empty?
  next if !opt_in_env.empty? && ENV[opt_in_env].to_s.empty?

  if bash_command
    effective_regex = build_bash_regex(rule, globs, pattern)
    next if effective_regex.nil?
    next unless effective_regex.match?(bash_command)
  else
    next if globs.empty?

    matches_file = globs.any? do |glob|
      File.fnmatch?(glob, relative_path, fnmatch_flags) ||
        File.fnmatch?(glob, file_path, fnmatch_flags)
    end
    next unless matches_file

    if pattern && !pattern.to_s.empty?
      begin
        regex = Regexp.new(pattern)
      rescue RegexpError
        warn("[personal-write-rules] invalid regex for rule '#{name}': #{pattern}")
        next
      end
      next unless regex.match?(new_content)
    end
  end

  context = static_context
  sentinel_suffix = nil

  unless context_script.empty?
    script_path = File.expand_path(context_script, project_dir)
    unless File.executable?(script_path)
      warn "[personal-write-rules] context_script not executable for '#{name}': #{script_path}"
      next
    end

    env = {
      "CLAUDE_FILE_PATH" => file_path,
      "CLAUDE_RELATIVE_PATH" => relative_path,
      "CLAUDE_SESSION_ID" => session_id
    }
    stdout_str, _status = Open3.capture2(env, script_path)
    lines = stdout_str.lines
    sentinel_suffix = lines.shift.sub("#sentinel-suffix:", "").strip if lines.first&.start_with?("#sentinel-suffix:")
    body = lines.join.strip
    next if body.empty?

    context = body
  end

  if ONCE_TYPES.include?(type)
    sentinel_name = (sentinel_suffix && !sentinel_suffix.empty?) ? "#{name}-#{sentinel_suffix}" : name
    sentinel = File.join(session_dir, sentinel_name)
    next if File.exist?(sentinel)

    sentinels_to_touch << sentinel
  end

  message = "[#{name}] #{context}"
  message = "#{message}\n\n#{BLOCK_ONCE_RETRY_HINT}" if type == "block_once"

  case type
  when "block", "block_once" then blocks << message
  when "warn", "warn_once" then warns << message
  end
end

if blocks.any? || warns.any?
  sentinels_to_touch.each do |sentinel|
    FileUtils.mkdir_p(File.dirname(sentinel))
    FileUtils.touch(sentinel)
  end
end

if blocks.any?
  reason = (blocks + warns).join("\n\n")
  puts JSON.generate(
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason
    }
  )
  exit 2
elsif warns.any?
  puts JSON.generate(
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: warns.join("\n\n")
    }
  )
end

exit 0
