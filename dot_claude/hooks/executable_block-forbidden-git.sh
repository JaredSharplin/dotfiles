#!/bin/bash
# PreToolUse hook - blocks raw git commands that should use git town instead

if [ "$CLAUDE_TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND="$CLAUDE_TOOL_INPUT"

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+checkout'; then
  echo "Blocked: Use 'git town hack <name>' to create branches or 'git town' commands to switch. Load /git-town skill." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+rebase'; then
  echo "Blocked: Use 'git town sync' instead of git rebase. Load /git-town skill." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push'; then
  echo "Blocked: Use 'git town sync' instead of git push. Load /git-town skill." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+stash'; then
  echo "Blocked: git stash is forbidden with git town. Git town auto-stashes. Load /git-town skill." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+clone'; then
  echo "Blocked: git clone is not needed. Work within existing worktrees." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+reset[[:space:]]+--hard'; then
  echo "Blocked: git reset --hard is destructive. Find a safer alternative." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+commit[[:space:]]+.*--amend'; then
  echo "Blocked: git commit --amend is forbidden. Create a new commit instead." >&2
  exit 2
fi

exit 0
