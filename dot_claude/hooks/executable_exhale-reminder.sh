#!/bin/bash
# PostToolUse hook on Bash + git commit — nudges Beck's exhale pass after a feature/fix commit.
# See global CLAUDE.md § Design rhythm for the rationale.
#
# Suppresses on:
#   - commits that were already a refactor pass (commit message contains refactor/simplify/exhale/cleanup)
#   - chore: / docs: type prefixes (no design surface)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only fire on `git commit` (subshell / && chain aware).
echo "$COMMAND" | grep -qE '(^|(&&|\|\||;|\|)[[:space:]]*)git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Already a refactor pass — exhale not needed.
if echo "$COMMAND" | grep -qiE "(refactor|simplify|exhale|cleanup|clean[[:space:]]+up)"; then
  exit 0
fi

# Conventional-commit type prefix indicates no design surface.
if echo "$COMMAND" | grep -qE -- "-m[[:space:]]*[\"']?(chore|docs)(\([^)]*\))?!?:"; then
  exit 0
fi

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Exhale. You just committed a feature/fix — now review for design quality before moving on. Apply Beck's four rules (CLAUDE.md § Design rhythm): passes tests? reveals intent? any duplication? could you remove elements? In payaus, invoke /simplify-with-analysis for the full chain (simplify → bin/diff-quality: rubycritic + SimpleCov coverage vs master). Otherwise /simplify is the built-in. Commit any cleanup separately from the feature commit you just made — never mix the two."
  }
}
JSON
exit 0
