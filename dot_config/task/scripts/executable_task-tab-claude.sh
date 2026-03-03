#!/usr/bin/env ruby
# frozen_string_literal: true

# Wrapper script for Claude in task workspace tabs.
# Session loop: re-checks context after each Claude session completes.
# - Review context: runs walkthrough then code review (two fresh sessions), then cleans up
# - Task context: runs implementation Claude fresh each time; after exit, auto-detects PR
#   annotation and triggers pr-review automatically
# - No context: runs bare Claude and exits

require "json"
require "open3"

CONTEXT_DIR = File.expand_path("~/.local/share/task/context")

def find_context
  return nil unless Dir.exist?(CONTEXT_DIR)

  dir = Dir.pwd
  Dir.glob(File.join(CONTEXT_DIR, "*.json"))
    .select { File.file?(it) }
    .reject { File.basename(it).start_with?("review-slot-") }
    .find do
      data = JSON.parse(File.read(it), symbolize_names: true) rescue next
      data[:project_dir] == dir
    end
end

def find_review_context
  return nil unless Dir.exist?(CONTEXT_DIR)

  dir = Dir.pwd
  Dir.glob(File.join(CONTEXT_DIR, "review-slot-*.json"))
    .select { File.file?(it) }
    .find do
      data = JSON.parse(File.read(it), symbolize_names: true) rescue next
      data[:project_dir] == dir
    end
end

def build_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)

  task_id    = data[:id].to_s
  description = data[:description].to_s
  project    = data[:project].to_s
  tags       = Array(data[:tags]).join(", ")
  annotations = Array(data[:annotations]).map { "- #{it}" }.join("\n")

  pr_annotation     = Array(data[:annotations]).select { it.match?(/^PR: /) }.last
  linear_annotation = Array(data[:annotations]).select { it.match?(/^Linear: /) }.last

  prereqs = []
  if linear_annotation
    linear_url = linear_annotation.sub(/^Linear: /, "")
    prereqs << "- Read the Linear ticket: #{linear_url}"
  end
  if pr_annotation
    pr_url    = pr_annotation.sub(/^PR: /, "")
    pr_number = pr_url.split("/").last&.gsub(/\D/, "")
    prereqs << "- Check PR status and open review comments: `gh pr view #{pr_number}`"
  end

  <<~PROMPT.chomp
    Task ##{task_id}: #{description}#{project.empty? ? "" : "\nProject: #{project}"}#{tags.empty? ? "" : "\nTags: #{tags}"}#{annotations.empty? ? "" : "\n\nAnnotations:\n#{annotations}"}#{prereqs.empty? ? "" : "\n\nBefore starting:\n#{prereqs.join("\n")}"}#{pr_annotation ? "\n\nPipeline commands (use these to advance PR status, not task annotate):\n  pr-review self   — mark self-review complete\n  pr-review qa     — mark QA done / ready for peer review" : ""}

    Investigate and plan the approach.
    Annotate key milestones as you work: `task #{task_id} annotate "..."`
  PROMPT
end

def build_walkthrough_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)

  case data
  in { pr_number:, title:, url: }
    <<~PROMPT.chomp
      Walkthrough: PR ##{pr_number} — #{title}
      URL: #{url}

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
end

def build_review_prompt(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)

  case data
  in { pr_number:, title:, author:, url: }
    <<~PROMPT.chomp
      Code review: PR ##{pr_number} — #{title}
      Author: #{author}
      URL: #{url}

      You are an independent reviewer who has not seen this code before.
      1. Load the code reviewer skill with 37 signals and ActiveRecord personalities.
      2. Run `gh pr diff #{pr_number}` to fetch the diff.
      3. Review the diff with a critical eye: correctness, edge cases, naming, design.
      4. Write your full review here in the terminal — do NOT post comments to GitHub.
    PROMPT
  end
end

def auto_trigger_review(context_file)
  data = JSON.parse(File.read(context_file), symbolize_names: true)
  task_id = data[:id]&.to_s
  return false if task_id.nil? || task_id.empty?

  export_json, = Open3.capture3("task", task_id, "export")
  exported = JSON.parse(export_json, symbolize_names: true) rescue []
  task_data = Array(exported).first
  return false unless task_data

  annotations = Array(task_data[:annotations])

  pr_annotation = annotations
    .select { it[:description]&.match?(/^PR: /) }
    .last
  return false unless pr_annotation

  already_self_reviewed = annotations.any? { it[:description]&.match?(/^Self-reviewed:/) }
  return false if already_self_reviewed

  pr_url    = pr_annotation[:description].sub(/^PR: /, "")
  pr_number = pr_url.split("/").last&.gsub(/\D/, "")
  return false if pr_number.nil? || pr_number.empty?

  system("pr-review", pr_number)
  true
end

def safe_delete(path)
  return unless path && File.exist?(path)

  if system("which", "trash", out: File::NULL, err: File::NULL)
    system("trash", path)
  else
    File.unlink(path)
  end
end

# Rename tab via shared script (silently ignore errors)
system("slot-rename-tab", err: File::NULL, out: File::NULL) rescue nil

# Session loop
loop do
  review_file  = find_review_context
  context_file = find_context

  if review_file
    # Walkthrough session
    walkthrough_prompt = build_walkthrough_prompt(review_file)
    system("claude", "--dangerously-skip-permissions", walkthrough_prompt)

    # Code review session (fresh context — walkthrough has ended)
    if File.exist?(review_file)
      review_prompt = build_review_prompt(review_file)
      system("claude", "--dangerously-skip-permissions", review_prompt)
    end

    # Auto-annotate task with Self-reviewed after code review (self-reviews only)
    if File.exist?(review_file)
      review_data = JSON.parse(File.read(review_file), symbolize_names: true) rescue {}
      if review_data[:is_self_review]
        sr_pr = review_data[:pr_number]&.to_s
        if sr_pr && !sr_pr.empty?
          active_json, = Open3.capture3("task", "+ACTIVE", "export")
          active_tasks = JSON.parse(active_json, symbolize_names: true) rescue []
          sr_task = Array(active_tasks).find do |t|
            Array(t[:annotations]).any? { it[:description]&.match?(/PR:.*#{Regexp.escape(sr_pr)}/) }
          end
          if sr_task
            system("task", sr_task[:id].to_s, "annotate", "Self-reviewed: PR ##{sr_pr}",
                   err: File::NULL)
          end
        end
      end
    end

    # Cleanup after both sessions complete
    slot_n = File.basename(review_file).match(/review-slot-(\d+)\.json/)&.[](1)

    safe_delete(review_file)

    if slot_n
      pr_marker = File.expand_path("~/programming/worktrees/slot-#{slot_n}/.pr-review")
      safe_delete(pr_marker)

      idle_dir = File.expand_path("~/programming/worktrees/slot-#{slot_n}")
      branch   = "slot-#{slot_n}"
      unless system("git", "-C", idle_dir, "checkout", branch, err: File::NULL, out: File::NULL)
        system("git", "-C", idle_dir, "checkout", "-b", branch, err: File::NULL, out: File::NULL)
      end
    end

    system("slot-rename-tab", err: File::NULL, out: File::NULL) rescue nil
    break

  elsif context_file
    prompt = build_prompt(context_file)
    system("claude", "--dangerously-skip-permissions", prompt)

    # Auto-detect unreviewed PR annotation and trigger review if found
    review_file = find_review_context
    if review_file.nil?
      auto_trigger_review(context_file) rescue nil
      review_file = find_review_context
    end
    break if review_file.nil?

  else
    exec("claude", "--dangerously-skip-permissions")
  end
end
