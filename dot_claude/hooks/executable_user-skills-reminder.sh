#!/bin/bash
# UserPromptSubmit hook — inject user-level skills into context

USER_SKILLS_DIR="$HOME/.claude/skills"
[ -d "$USER_SKILLS_DIR" ] || exit 0

OUTPUT="📚 User skills (~/.claude/skills):"
for skill_dir in "$USER_SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  OUTPUT="$OUTPUT\n• $(basename "$skill_dir")"
done

printf "%b\n" "$OUTPUT"
