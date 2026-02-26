#!/usr/bin/env bash
# Wrapper script for Claude in task workspace tabs.
# Session loop: re-checks context after each Claude session completes.
# - Review context: runs walkthrough then code review (two fresh sessions), then cleans up
# - Task context: runs implementation Claude; after exit, auto-detects PR annotation and
#   triggers pr-review automatically — no explicit call from Claude required
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
  local description project tags annotations prompt

  description=$(jq -r '.description // empty' "$context_file")
  project=$(jq -r '.project // empty' "$context_file")
  tags=$(jq -r '(.tags // []) | join(", ")' "$context_file")
  annotations=$(jq -r '(.annotations // []) | map("- " + .) | join("\n")' "$context_file")

  prompt="Task: ${description}"

  if [[ -n "$project" ]]; then
    prompt="${prompt}\nProject: ${project}"
  fi

  if [[ -n "$tags" ]]; then
    prompt="${prompt}\nTags: ${tags}"
  fi

  if [[ -n "$annotations" ]]; then
    prompt="${prompt}\n\nContext:\n${annotations}"
  fi

  prompt="${prompt}\n\nInvestigate and plan the approach for this task."

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
  prompt="${prompt}\n2. Give a 2-3 sentence summary: what this PR does and why."
  prompt="${prompt}\n3. Walk through each changed file one at a time:"
  prompt="${prompt}\n   - What changed and why (not just what, but the reasoning behind the approach)"
  prompt="${prompt}\n   - Any non-obvious logic, edge cases, or future maintenance implications"
  prompt="${prompt}\n   - Stop after each file and ask if I have questions before continuing"
  prompt="${prompt}\n4. After all files, ask if anything is still unclear."

  if [[ "$is_self_review" == "true" ]]; then
    prompt="${prompt}\n5. When I confirm I understand, find the active task for this PR:"
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
  prompt="${prompt}\n2. Review with 37signals and ActiveRecord personalities (use the code reviewer skill)."
  prompt="${prompt}\n3. Post inline review comments and a summary."

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
    # Walkthrough session — resumable if interrupted
    walkthrough_session_id=$(jq -r '.walkthrough_session_id // empty' "$review_file")
    walkthrough_prompt=$(build_walkthrough_prompt "$review_file")
    if [[ -n "$walkthrough_session_id" ]]; then
      claude --session-id "$walkthrough_session_id" --dangerously-skip-permissions "$walkthrough_prompt"
    else
      claude --dangerously-skip-permissions "$walkthrough_prompt"
    fi

    # Code review session — resumable if interrupted
    if [[ -f "$review_file" ]]; then
      review_session_id=$(jq -r '.review_session_id // empty' "$review_file")
      review_prompt=$(build_review_prompt "$review_file")
      if [[ -n "$review_session_id" ]]; then
        claude --session-id "$review_session_id" --dangerously-skip-permissions "$review_prompt"
      else
        claude --dangerously-skip-permissions "$review_prompt"
      fi
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
    # Use the task UUID as session ID — creates on first run, resumes on re-activation,
    # naturally isolated per task (different task = different UUID = fresh session)
    prompt=$(build_prompt "$context_file")
    context_basename=$(basename "$context_file" .json)
    claude --session-id "$context_basename" --dangerously-skip-permissions "$prompt"

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
