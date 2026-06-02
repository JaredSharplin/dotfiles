---
name: handoff
description: >
  Generate comprehensive handoff instructions so a fresh Claude session can
  seamlessly continue the current work. Use when the user invokes /handoff or
  asks to "hand off this work", "write a handoff", or "prepare context for a new
  session". Writes the handoff to a file in ~/.claude/plans/ and returns a short
  prompt to copy-paste into the new session.
---

# Context Handoff

Capture everything a fresh Claude session needs to continue this work without re-asking, write it to a persistent handoff file, and hand back a short prompt that points the new session at that file.

**Reference, don't duplicate.** Don't restate content that already lives in another artifact — plans, PR descriptions, commits, the diff, feature specs. Point to them by path or URL and summarize only what's needed to orient. The handoff is a map to the context, not a copy of it.

## Step 1: Gather context

Run these to establish current state:

```bash
# Git context
git branch --show-current
git log --oneline -5
git status --porcelain
git diff --stat

# Check for PR
gh pr view --json number,title,url,state 2>/dev/null || echo "No PR"

# Recent plans (handoffs live here too)
ls -lt ~/.claude/plans/ | head -10
```

## Step 2: Reflect on session context

Think about:
- What plans from `~/.claude/plans/` have you referenced this session?
- What files have you read or modified?
- What is the overall goal of this work?
- What decisions were made and why?
- What gotchas or important context would otherwise be lost?

## Step 3: Write the handoff file

Pick a short, descriptive kebab-case slug for the work (e.g. `mds-v2-filters`) and write the handoff to:

```
~/.claude/plans/<slug>-handoff.md
```

If a handoff for the same work already exists at that path, overwrite it. Use this structure for the file contents:

```markdown
# Continue This Work

## Context
- **Directory:** [current working directory]
- **Branch:** [branch name]
- **Goal:** [1-2 sentence description of what we're building/fixing]

## Read These Plans First
[Full paths to relevant plans from ~/.claude/plans/ this session has used]
- `~/.claude/plans/plan-name.md` - [brief description]

## Pull Request
[PR URL if exists, otherwise "No PR created yet"]

## Key Files
[Files central to the work - ones you've been reading/modifying]
- `path/to/file.rb` - [why it matters]

## Feature Specification
[If applicable, path to feature spec - check .claude/features.yml]

## Progress
### Completed
- [what has been done]

### In Progress
- [what was being worked on]

### Remaining
- [what still needs to be done]

## Critical Context
[Important decisions, gotchas, edge cases, or context that would otherwise be lost]

## Suggested Skills
[Skills the next session should invoke for this work, e.g. "/git-town to open the PR", "/tdd-bug-fix to continue the failing test". Omit if none apply.]

## Your Task
[Clear instruction for what to do next, e.g., "Continue implementing X by doing Y"]
```

The file must be comprehensive enough that a fresh session can continue without asking clarifying questions about context.

## Step 4: Return the copy-paste prompt

After writing the file, output **only** a short prompt for the user to paste into a new Claude session — inside a single code fence, nothing else after it:

```
Read ~/.claude/plans/<slug>-handoff.md and continue the work described there.
```
