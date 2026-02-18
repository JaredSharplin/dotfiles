# Context Handoff Command

Generate comprehensive handoff instructions that can be copy-pasted to a new Claude session to seamlessly continue this work.

## Step 1: Gather Context

Run these commands to gather current state:

```bash
# Git context
git branch --show-current
git log --oneline -5
git status --porcelain
git diff --stat

# Check for PR
gh pr view --json number,title,url,state 2>/dev/null || echo "No PR"

# List recent plans
ls -lt ~/.claude/plans/ | head -10
```

## Step 2: Reflect on Session Context

Think about:
- What plans from `~/.claude/plans/` have you referenced in this session?
- What files have you read or modified?
- What is the overall goal of this work?
- What decisions were made and why?
- What gotchas or important context would be lost?

## Step 3: Output Handoff Instructions

Output a single markdown block inside a code fence that the user can copy-paste as their first message to a new Claude session. Use this structure:

```markdown
# Continue This Work

## Context
- **Directory:** [current working directory]
- **Branch:** [branch name]
- **Goal:** [1-2 sentence description of what we're building/fixing]

## Read These Plans First
[List full paths to relevant plans from ~/.claude/plans/ that this session has been using]
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

## Your Task
[Clear instruction for what to do next, e.g., "Continue implementing X by doing Y"]
```

**Important:** The output must be comprehensive enough that a fresh Claude session can continue without asking clarifying questions about context.
