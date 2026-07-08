---
name: capture-rule
description: >
  Route a correction back into the Claude harness so the mistake doesn't repeat.
  Given something Claude got wrong in this session, decide where the rule should
  live (global CLAUDE.md, project CLAUDE.md, write-rules.yml, a new hook, a skill
  trigger), draft the wording, and write it after the user confirms. Use when the
  user invokes /capture-rule or says "codify this", "make this a rule", "remember
  this so Claude stops doing it", "add a guard for this".
---

# Capture rule

A correction that lives only in the chat ends with the chat. This skill takes a specific mistake from the current session and turns it into a durable rule in the right artifact — so future sessions don't repeat the error.

The skill does the *routing* work that built-in `/remember` doesn't do: it picks between scopes (global vs project) and enforcement shapes (prose nudge vs hard block vs warn vs dynamic context vs skill trigger), proposes the exact wording, and writes the change after the user confirms via AskUserQuestion.

**Human gate is non-negotiable.** Auto-capture without review is a documented failure mode in this space (Cursor pulled then re-added rule generation; Windsurf has memory-amplification risk). Every rule lands only on explicit confirmation.

## Step 1: Identify the specific mistake

Look at the conversation. Find the concrete thing Claude did wrong. Not the user's framing of it — the actual action and the better action. If unclear, ask one targeted question via AskUserQuestion (not three). Don't proceed on a fuzzy understanding.

Anchor on:
- What Claude did (the actual command / edit / decision).
- Why it was wrong (rule violated, convention skipped, tool misused).
- What the correct behaviour was (the user's correction or the right path).

## Step 2: Classify scope

| Scope | Destination |
|---|---|
| Cross-project, language-agnostic (e.g. "quote paths with spaces") | Global `~/.claude/CLAUDE.md` — chezmoi source `~/.local/share/chezmoi/dot_claude/CLAUDE.md` |
| Cross-project, language/tool-specific (e.g. all Ruby work) | Global `CLAUDE.md` section, or a new global skill if it's a workflow |
| Project-specific to payaus | `~/programming/payaus/.claude/` artifacts |
| Project-specific to another repo | That repo's `.claude/` or `CLAUDE.md` |

If you can't tell, default to project scope — narrower is safer than broader.

## Step 3: Classify enforcement shape

| Shape | When to use | Destination |
|---|---|---|
| Prose nudge | Most cases — a guideline Claude should know but not a hard rule | Append to the right `CLAUDE.md` section |
| Hard block on file pattern | "Never write X in Y file" — must not happen | New `write-rules.yml` rule with `type: block` or `block_once` |
| Soft warn on file pattern | "When editing X, consider Y first" — nudge, not deny | New `write-rules.yml` rule with `type: warn_once` |
| Shell command shape block | "Never set env X" / "don't run command Y" | New `write-rules.yml` rule with `bash_pattern` |
| Dynamic context | "When editing X, surface specific info about it" | New `context_script` referenced from a write-rules entry |
| Skill trigger expansion | "Before X, use the Y skill" — extend an existing skill's triggers | Add to the relevant `SKILL.md` description |

When choosing between block and warn: block when the wrong action is genuinely unrecoverable or expensive; warn when it's a nudge to think twice. Default to warn — blocks accumulate friction quickly.

## Step 4: Draft the wording

Write the rule in the voice of the destination. CLAUDE.md prose is direct and second-person. Write-rules `context` blocks are imperative and explain *why*. The wording should make the *reason* clear so Claude can reason about edge cases, not just pattern-match.

Bad: "Don't use `bin/dev console`."
Good: "Don't use `bin/dev console` for code exploration — it hits the shared remote dev DB. Use `bin/rails console` for local DB work (native dev), or Grep/Read for code reading."

## Step 5: Propose via AskUserQuestion

Use AskUserQuestion with at most two options: the recommended placement, and the next-best alternative. Include previews showing the literal new text and the file path that will be edited. Don't bury the proposal in prose — show the actual diff in the preview.

If the recommendation involves a new hook script or skill scaffold, the preview should show the file tree being created, not the entire script body. Confirm structure first, then write.

## Step 6: Write the change

On confirmation:

- **Chezmoi source files** (`dot_claude/*`): resolve via `chezmoi source-path ~/.claude/<deployed-path>`, edit the source, then run `chezmoi apply -v` to deploy.
- **Project files** (anywhere under a working repo's `.claude/`): edit in place.
- **New hook scripts**: `chmod +x` after creation (chezmoi sources use the `executable_` prefix instead).
- **New skills**: scaffold the `SKILL.md` directory with frontmatter (`name` and `description`) and body.

After writing, summarize: file path, what was added, and whether deployment ran. Don't commit — leave changes for the user's normal git workflow.

## Don't

- **Don't auto-commit.** Per global CLAUDE.md, commits happen when a logical unit of work is complete, not after every edit.
- **Don't write rules without the user confirming via AskUserQuestion.** Even if the correction is clear-cut, the routing decision still needs sign-off.
- **Don't add a hook or skill when a CLAUDE.md line would do.** Start with prose; promote to a structural enforcement mechanism only when the rule needs that level of guard.
- **Don't restate context from the conversation in the rule.** The rule should stand on its own — "we don't do X here because Y", not "earlier you mentioned X".
- **Don't expand scope to fix related issues.** One correction, one rule. If you notice an adjacent problem, surface it but don't fold it into this rule.

## When to refuse

If the user invokes this skill but no specific correction is identifiable in the session, say so and ask for the specific behaviour to codify. Don't generate a generic "be more careful" rule — it teaches nothing and adds noise to the rule files.
