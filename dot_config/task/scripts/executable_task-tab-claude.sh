#!/usr/bin/env ruby
# frozen_string_literal: true

# Wrapper script for Claude in task workspace tabs.
# Session loop: re-checks context after each Claude session completes.
# - Review stage (self-review/peer-review): runs walkthrough then code review
# - Task stage (execute/qa): runs implementation Claude; after exit, auto-advances to self-review
#   if a PR: annotation is present and stage is still execute
# - No context: runs bare Claude and exits

require "json"
require "open3"

CONTEXT_DIR = File.expand_path("~/.local/share/task/context")

def find_context
  return nil unless Dir.exist?(CONTEXT_DIR)

  dir = Dir.pwd
  Dir.glob(File.join(CONTEXT_DIR, "*.json"))
    .select { File.file?(it) }
    .find do
      data = JSON.parse(File.read(it), symbolize_names: true) rescue next
      data[:project_dir] == dir
    end
end

def review_stage?(context_file)
  return false unless context_file

  data = JSON.parse(File.read(context_file), symbolize_names: true) rescue {}
  %w[self-review peer-review].include?(data[:stage].to_s)
end

def build_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)

  task_id     = data[:id].to_s
  description = data[:description].to_s
  project     = data[:project].to_s
  tags        = Array(data[:tags]).join(", ")
  annotations = Array(data[:annotations]).map { "- #{it}" }.join("\n")

  pr_annotation     = Array(data[:annotations]).find { it.match?(/\APR: /) }
  linear_annotation = Array(data[:annotations]).find { it.match?(/\ALinear: /) }

  pr_url = data[:pr_url] || pr_annotation&.sub(/\APR: /, "")
  pr_number = pr_url&.split("/")&.last&.gsub(/\D/, "")

  prereqs = []
  if linear_annotation
    linear_url = linear_annotation.sub(/\ALinear: /, "")
    prereqs << "- Read the Linear ticket: #{linear_url}"
  end
  if pr_number
    prereqs << "- Check PR status and open review comments: `gh pr view #{pr_number}`"
  end

  pipeline_hint = pr_url ? "\n\nPipeline commands (use these to advance PR status):\n  t review   — start self-review\n  t qa       — mark QA done / ready for peer review" : ""

  <<~PROMPT.chomp
    Task ##{task_id}: #{description}#{project.empty? ? "" : "\nProject: #{project}"}#{tags.empty? ? "" : "\nTags: #{tags}"}#{annotations.empty? ? "" : "\n\nAnnotations:\n#{annotations}"}#{prereqs.empty? ? "" : "\n\nBefore starting:\n#{prereqs.join("\n")}"}#{pipeline_hint}

    Investigate and plan the approach.
    Annotate key milestones as you work: `task #{task_id} annotate "..."`
  PROMPT
end

def build_walkthrough_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)
  pr_url    = data[:pr_url].to_s
  pr_number = pr_url.split("/").last.gsub(/\D/, "")
  title     = data[:description].to_s

  <<~PROMPT.chomp
    Walkthrough: PR ##{pr_number} — #{title}
    URL: #{pr_url}

    1. Understand the problem — before looking at any code:
       a. Read the PR description: `gh pr view #{pr_number}`
       b. Follow any linked Linear tickets, referenced PRs, or documentation URLs in the description and read them too.
       c. Summarise the PROBLEM in 2-3 sentences — what is broken or missing, and why does it matter. Do not describe the solution yet.
    2. Run `gh pr diff #{pr_number}` to fetch the diff.
    3. Sort the changed files into this reading order before starting: tests first, then models/data layer, then service/domain logic, then controllers/jobs/views, then config and migrations last. State the order you'll follow before beginning.
    4. For each changed file, in that order: one plain-English sentence on what this file's role is in the change. No code snippets.
    5. After all files, ask if anything is still unclear.
    6. Print a glossary of business and domain terms a new developer would need to understand this PR — things like 'Leave Award', 'Employment Condition Set', 'TOIL'. Explicitly exclude method names, class names, and Ruby API. One plain-English definition sentence each.
  PROMPT
end

def build_review_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)
  pr_url    = data[:pr_url].to_s
  pr_number = pr_url.split("/").last.gsub(/\D/, "")
  title     = data[:description].to_s

  # Fetch author from gh if not cached in context
  author = data[:author].to_s
  if author.empty?
    pr_json = `gh pr view #{pr_number} --json author -q '.author.login' 2>/dev/null`.strip
    author = pr_json unless pr_json.empty?
  end

  <<~PROMPT.chomp
    Code review: PR ##{pr_number} — #{title}#{author.empty? ? "" : "\nAuthor: #{author}"}
    URL: #{pr_url}

    You are an independent reviewer who has not seen this code before.
    1. Load the code reviewer skill with 37 signals and ActiveRecord personalities.
    2. Run `gh pr diff #{pr_number}` to fetch the diff.
    3. Review the diff with a critical eye: correctness, edge cases, naming, design.
    4. Write your full review here in the terminal — do NOT post comments to GitHub.
  PROMPT
end

def auto_trigger_review(context_file)
  data    = JSON.parse(File.read(context_file), symbolize_names: true)
  task_id = data[:id]&.to_s
  return false if task_id.nil? || task_id.empty?

  # Use pr_url from context if already set; otherwise look for PR: annotation
  pr_url = data[:pr_url]
  unless pr_url
    export_json, = Open3.capture3("task", task_id, "export")
    exported     = JSON.parse(export_json, symbolize_names: true) rescue []
    task_data    = Array(exported).first
    return false unless task_data

    pr_annotation = Array(task_data[:annotations])
      .find { it[:description]&.match?(/\APR: /) }
    return false unless pr_annotation

    pr_url = pr_annotation[:description].sub(/\APR: /, "")
  end

  pr_number = pr_url.split("/").last.gsub(/\D/, "")
  return false if pr_number.empty?

  system("t", "review", pr_number)
  true
end

# Rename tab via shared script (silently ignore errors)
system("slot-rename-tab", err: File::NULL, out: File::NULL) rescue nil

# Session loop
loop do
  context_file = find_context

  if context_file && review_stage?(context_file)
    # Walkthrough session
    walkthrough_prompt = build_walkthrough_prompt(context_file)
    system("claude", "--dangerously-skip-permissions", walkthrough_prompt)

    # Code review session (fresh context — walkthrough has ended)
    context_file = find_context
    if context_file && review_stage?(context_file)
      review_prompt = build_review_prompt(context_file)
      system("claude", "--dangerously-skip-permissions", review_prompt)
    end

    # After review sessions: peer-review tasks are done; self-review stays active for t qa
    context_file = find_context
    if context_file
      data = JSON.parse(File.read(context_file), symbolize_names: true) rescue {}
      if data[:stage] == "peer-review"
        system("t", "done")
      end
    end

    system("slot-rename-tab", err: File::NULL, out: File::NULL) rescue nil
    break

  elsif context_file
    prompt = build_prompt(context_file)
    system("claude", "--dangerously-skip-permissions", prompt)

    # Auto-advance to self-review if execute stage and PR annotation found
    context_file = find_context
    if context_file
      data = JSON.parse(File.read(context_file), symbolize_names: true) rescue {}
      if data[:stage].to_s == "execute" || data[:stage].nil?
        triggered = auto_trigger_review(context_file) rescue false
        break unless triggered
        # Loop continues — next iteration will detect review stage
      else
        break
      end
    else
      break
    end

  else
    exec("claude", "--dangerously-skip-permissions")
  end
end
