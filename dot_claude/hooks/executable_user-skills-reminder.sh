#!/bin/bash
# UserPromptSubmit hook — inject user-level skills into context
# These skills MUST be checked alongside project skills in any pre-flight skill check.

USER_SKILLS_DIR="$HOME/.claude/skills"
[ -d "$USER_SKILLS_DIR" ] || exit 0

SKILLS=""
for skill_dir in "$USER_SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  SKILLS="$SKILLS\n• $(basename "$skill_dir")"
done

printf "%b\n" "📚 User skills (~/.claude/skills) — ALSO check these in any skill pre-flight:$SKILLS"
