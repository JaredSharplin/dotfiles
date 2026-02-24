#!/usr/bin/env bash
# Wrapper script for Claude in task workspace tabs.
# Reads task context from ~/.local/share/task/context/ and launches Claude
# in plan mode with the task description as the initial prompt.

set -euo pipefail

CONTEXT_DIR="$HOME/.local/share/task/context"

# Find context file matching current working directory
find_context() {
  local dir="$PWD"
  if [[ ! -d "$CONTEXT_DIR" ]]; then
    return 1
  fi

  for f in "$CONTEXT_DIR"/*.json; do
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

context_file=$(find_context) || true

if [[ -n "$context_file" ]]; then
  prompt=$(build_prompt "$context_file")
  exec claude --dangerously-skip-permissions "$prompt"
else
  exec claude --dangerously-skip-permissions
fi
