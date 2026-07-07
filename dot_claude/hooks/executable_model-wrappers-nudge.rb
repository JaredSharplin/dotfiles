#!/usr/bin/env ruby
# frozen_string_literal: true

# model-wrappers-nudge.rb — PreToolUse hook on Edit / MultiEdit / Write.
#
# When editing a root AR model (`app/models/<name>.rb`) that has sibling
# wrappers under `app/models/<name>/`, inject an advisory listing the existing
# wrappers and prompting "does this belong on the root, or in a wrapper?".
#
# Project-agnostic — only fires when the file path matches `*/app/models/*.rb`
# (top-level model file, not a wrapper file at `app/models/<ns>/<x>.rb`) AND
# there's an actual sibling directory with .rb files. No-op everywhere else.
# No session sentinel — fires on every matching edit, accepting mild repetition
# in exchange for simplicity.

require "json"

input = JSON.parse($stdin.read) rescue exit(0)

tool = input["tool_name"].to_s
exit 0 unless %w[Edit MultiEdit Write].include?(tool)

file = input.dig("tool_input", "file_path").to_s
exit 0 if file.empty?

# Match top-level app/models/<name>.rb only — skip wrappers themselves
# (app/models/<ns>/<x>.rb).
m = file.match(%r{/app/models/([^/]+)\.rb\z}) or exit(0)
model_name = m[1]

# Skip ApplicationRecord — the wrapper pattern doesn't apply.
exit 0 if model_name == "application_record"

model_dir = File.join(File.dirname(file), model_name)
exit 0 unless File.directory?(model_dir)

wrappers = Dir.children(model_dir)
  .select { |f| f.end_with?(".rb") }
  .map { |f| f.sub(/\.rb\z/, "") }
  .sort

exit 0 if wrappers.empty?

# Cap inline list at 15 names; payaus's biggest model (payroll) has ~90.
LIST_CAP = 15
listed = wrappers.length > LIST_CAP ?
  "#{wrappers.first(LIST_CAP).join(", ")} (+#{wrappers.length - LIST_CAP} more)" :
  wrappers.join(", ")

advisory = <<~MSG.strip
  Editing root model `#{model_name}` — #{wrappers.length} existing wrapper#{'s' if wrappers.length != 1} under `app/models/#{model_name}/`: #{listed}.

  Before adding the new behaviour to the root model, ask:
  - Does this duplicate logic already in one of the wrappers above?
  - Does this represent a cohesive new responsibility — i.e. a signal to extract a new wrapper alongside the existing ones?
  - Is the logic genuinely a property of the root model with live callers reaching the root method directly?

  Prefer composition over inheritance to avoid god-object growth on root models. As `#{model_name}` accumulates responsibilities, the case for extracting a wrapper gets stronger. Only delegate from the root when there are live callers — grep before adding to a delegate list.
MSG

puts JSON.generate(
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: advisory,
  }
)
