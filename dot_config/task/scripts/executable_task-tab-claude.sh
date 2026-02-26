#!/usr/bin/env bash
# Wrapper script for Claude in task workspace tabs.
# Session loop: re-checks context after each Claude session completes.
# - Review context: runs walkthrough then code review (two fresh sessions), then cleans up
# - Task context: runs implementation Claude fresh each time; after exit, auto-detects PR
#   annotation and triggers pr-review automatically
# - No context: runs bare Claude and exits

set -euo pipefail

CONTEXT_DIR="$HOME/.local/share/task/context"

# Find task context file matching current working directory (excludes review files)
find_context() {
  local dir="$PWD"
  [[ -d "$CONTEXT_DIR" ]] || return 1

  for f in "$CONTEXT_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == review-slot-* ]] && continue
    local project_dir
    project_dir=$(jq -r '.project_dir // empty' "$f" 2>/dev/null)
    if [[ "$project_dir" == "$dir" ]]; then
      echo "$f"
      return 0
    fi
  done

  return 1
}

# Find review context file matching current working directory
find_review_context() {
  local dir="$PWD"
  [[ -d "$CONTEXT_DIR" ]] || return 1

  for f in "$CONTEXT_DIR"/review-slot-*.json; do
    [[ -f "$f" ]] || continue
    local project_dir
    project_dir=$(jq -r '.project_dir // empty' "$f" 2>/dev/null)
    if [[ "$project_dir" == "$dir" ]]; then
      echo "$f"
      return 0
    fi
  done

  return 1
}

build_prompt() {
  local context_file="$1"
  local task_id description project tags annotations prompt
  local pr_annotation linear_annotation prereqs

  task_id=$(jq -r '.id // empty' "$context_file")
  description=$(jq -r '.description // empty' "$context_file")
  project=$(jq -r '.project // empty' "$context_file")
  tags=$(jq -r '(.tags // []) | join(", ")' "$context_file")
  annotations=$(jq -r '(.annotations // []) | map("- " + .) | join("\n")' "$context_file")
  pr_annotation=$(jq -r '(.annotations // []) | map(select(test("^PR: "))) | last // empty' "$context_file")
  linear_annotation=$(jq -r '(.annotations // []) | map(select(test("^Linear: "))) | last // empty' "$context_file")

  prompt="Task #${task_id}: ${description}"

  if [[ -n "$project" ]]; then
    prompt="${prompt}\nProject: ${project}"
  fi

  if [[ -n "$tags" ]]; then
    prompt="${prompt}\nTags: ${tags}"
  fi

  if [[ -n "$annotations" ]]; then
    prompt="${prompt}\n\nAnnotations:\n${annotations}"
  fi

  prereqs=""
  if [[ -n "$linear_annotation" ]]; then
    linear_url="${linear_annotation#Linear: }"
    prereqs="${prereqs}\n- Read the Linear ticket: ${linear_url}"
  fi
  if [[ -n "$pr_annotation" ]]; then
    pr_url="${pr_annotation#PR: }"
    pr_number="${pr_url##*/}"
    pr_number="${pr_number//[^0-9]/}"
    prereqs="${prereqs}\n- Check PR status and open review comments: \`gh pr view ${pr_number}\`"
  fi

  if [[ -n "$prereqs" ]]; then
    prompt="${prompt}\n\nBefore starting:${prereqs}"
  fi

  prompt="${prompt}\n\nInvestigate and plan the approach."
  prompt="${prompt}\nAnnotate key milestones as you work: \`task ${task_id} annotate \"...\"\`"

  printf '%b' "$prompt"
}

build_walkthrough_prompt() {
  local context_file="$1"
  local pr_number title url is_self_review prompt

  pr_number=$(jq -r '.pr_number // empty' "$context_file")
  title=$(jq -r '.title // empty' "$context_file")
  url=$(jq -r '.url // empty' "$context_file")
  is_self_review=$(jq -r '.is_self_review // false' "$context_file")

  prompt="Walkthrough: PR #${pr_number} — ${title}"
  prompt="${prompt}\nURL: ${url}"
  prompt="${prompt}\n\n1. Run \`gh pr diff ${pr_number}\` to fetch the diff."
  prompt="${prompt}\n2. Generate a Mermaid diagram of the PR's structure (flowchart for features/bug fixes, sequence for API/job flows, class for model changes). Render it: printf '%%s' '<diagram>' | mermaid-ascii — then explain what it shows in 2-3 sentences."
  prompt="${prompt}\n3. Sort the changed files into this reading order before starting: tests first, then models/data layer, then service/domain logic, then controllers/jobs/views, then config and migrations last. State the order you'll follow before beginning."
  prompt="${prompt}\n4. For each changed file, in that order:"
  prompt="${prompt}\n   a. Tests as spec: find the corresponding test file(s), extract the test/describe/it descriptions as a bulleted spec outline — present this BEFORE looking at the implementation."
  prompt="${prompt}\n   b. Before/After: two plain-English sentences — what this file did before this PR, and what it does now."
  prompt="${prompt}\n   c. Walk through the implementation: what changed, why, non-obvious logic and edge cases."
  prompt="${prompt}\n      Analogy bridge: if you encounter an unfamiliar design pattern or architectural concept, explain it with a structurally precise real-world analogy before the technical explanation."
  prompt="${prompt}\n   d. Stop and ask if I have questions before continuing to the next file."
  prompt="${prompt}\n5. After all files, ask if anything is still unclear."
  prompt="${prompt}\n6. Print a vocabulary glossary: a table of new terms, abstractions, or domain concepts introduced in this PR — one plain-English definition sentence each, and which file they first appeared in."

  if [[ "$is_self_review" == "true" ]]; then
    prompt="${prompt}\n7. When I confirm I understand, find the active task for this PR:"
    prompt="${prompt}\n   \`task +ACTIVE export | jq '.[] | select(.annotations[]?.description | test(\"PR:.*${pr_number}\"))'\`"
    prompt="${prompt}\n   Then annotate it: \`task <id> annotate \"Self-reviewed: <one-line summary>\"\`"
  fi

  printf '%b' "$prompt"
}

build_review_prompt() {
  local context_file="$1"
  local pr_number title author url prompt

  pr_number=$(jq -r '.pr_number // empty' "$context_file")
  title=$(jq -r '.title // empty' "$context_file")
  author=$(jq -r '.author // empty' "$context_file")
  url=$(jq -r '.url // empty' "$context_file")

  prompt="Code review: PR #${pr_number} — ${title}"
  prompt="${prompt}\nAuthor: ${author}"
  prompt="${prompt}\nURL: ${url}"
  prompt="${prompt}\n\nYou are an independent reviewer who has not seen this code before."
  prompt="${prompt}\n1. Run \`gh pr diff ${pr_number}\` to fetch the diff."
  prompt="${prompt}\n2. Review the diff with a critical eye: correctness, edge cases, naming, design."
  prompt="${prompt}\n3. Write your full review here in the terminal — do NOT post comments to GitHub."

  printf '%b' "$prompt"
}

# Check task for an unreviewed PR annotation and call pr-review if found.
# Returns 0 if pr-review was triggered, 1 otherwise.
auto_trigger_review() {
  local context_file="$1"
  local task_id pr_annotation pr_url pr_number already

  task_id=$(jq -r '.id // empty' "$context_file" 2>/dev/null)
  [[ -n "$task_id" ]] || return 1

  pr_annotation=$(task "$task_id" export 2>/dev/null \
    | jq -r '.[0].annotations // [] | map(select(.description | test("^PR: "))) | last | .description // empty')
  [[ -n "$pr_annotation" ]] || return 1

  # Skip if already self-reviewed
  already=$(task "$task_id" export 2>/dev/null \
    | jq -r '[.[0].annotations // [] | .[] | select(.description | test("^Self-reviewed:"))] | length')
  [[ "$already" == "0" ]] || return 1

  pr_url="${pr_annotation#PR: }"
  pr_number="${pr_url##*/}"
  pr_number="${pr_number//[^0-9]/}"
  [[ -n "$pr_number" ]] || return 1

  pr-review "$pr_number"
}

# Rename tab via shared script
slot-rename-tab 2>/dev/null || true

# Session loop
while true; do
  review_file=$(find_review_context) || true
  context_file=$(find_context) || true

  if [[ -n "$review_file" ]]; then
    # Walkthrough session
    walkthrough_prompt=$(build_walkthrough_prompt "$review_file")
    claude --dangerously-skip-permissions "$walkthrough_prompt"

    # Code review session (fresh context — walkthrough has ended)
    if [[ -f "$review_file" ]]; then
      review_prompt=$(build_review_prompt "$review_file")
      claude --dangerously-skip-permissions "$review_prompt"
    fi

    # Cleanup after both sessions complete
    trash "$review_file" 2>/dev/null || rm -f "$review_file"
    # Remove .pr-review marker if this was an external review
    slot_n_from_file=$(basename "$review_file" | sed -n 's/review-slot-\([0-9]*\)\.json/\1/p')
    if [[ -n "$slot_n_from_file" ]]; then
      pr_marker="$HOME/programming/worktrees/slot-$slot_n_from_file/.pr-review"
      trash "$pr_marker" 2>/dev/null || rm -f "$pr_marker"
    fi
    slot-rename-tab 2>/dev/null || true
    break

  elif [[ -n "$context_file" ]]; then
    prompt=$(build_prompt "$context_file")
    claude --dangerously-skip-permissions "$prompt"

    # Auto-detect unreviewed PR annotation and trigger review if found
    review_file=$(find_review_context) || true
    if [[ -z "$review_file" ]]; then
      auto_trigger_review "$context_file" 2>/dev/null || true
      review_file=$(find_review_context) || true
    fi
    [[ -n "$review_file" ]] || break

  else
    claude --dangerously-skip-permissions
    break
  fi
done
