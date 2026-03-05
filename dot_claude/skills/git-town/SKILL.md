---
name: git-town
description: Use this skill when working with git branches, creating PRs, or managing stacked changes. Triggers include "create branch", "new feature branch", "git town", "stacked PR", "split PR", "rebase", "resolve conflicts", "checkout branch", "adopt PR", "work on someone's PR", "merge conflicts", or any branch management operations. MUST be loaded before any git checkout, git rebase, git push, git stash, git clone, or branch switching operation. (user)
---

# Git Town Stacked Changes Guide

Git Town enables efficient stacked changes development - building hierarchical feature branches where each branch depends on the previous one. This guide focuses on the essential commands for Claude Code to assist with stacked workflows.

Use appropriate prefixes for branches, like `feature/`, `hotfix/`, `refactor/` etc.

## Quick Task-to-Command Reference

| If you want to... | Use this command | Notes |
|---|---|---|
| Start a new feature branch | `git town hack <name>` | Creates branch from main |
| Update current branch with latest changes | `git town sync` | Syncs the current branch with its parent |
| Update stacked branches with latest changes | `git town sync -s` | Syncs entire stack safely |
| Add a child branch to current branch | `git town append <name>` | Build stack downward |
| Insert a parent branch above current | `git town prepend <name>` | Build stack upward |
| Create PR for current branch | `git town propose --title "..." --body "..."` | Then `gh pr edit --add-assignee @me --add-label <label>` |
| Change parent-child relationships | `git town set-parent <branch>` | Reorganize stack structure |

## When to Use Git Town vs Standard Git

**Use Git Town for:**
- Branch creation and hierarchy management (`hack`, `append`, `prepend`)
- Keeping stacks synchronized (`sync`)
- Creating PRs (`propose`)
- Modifying stack relationships (`set-parent`)

**Use standard Git for:**
- Checking status and history (`git status`, `git log`)

## Core Stacked Changes Commands

### `git town hack <branch-name>`
**Purpose:** Start a new feature branch from main
**When to use:** Beginning any new feature or task
**Example:** `git town hack feature/user-auth`

### `git town sync`
**Purpose:** Update current branch with latest changes from parent and remote
**When to use:**
- Before starting work each day
- Before creating PRs
- After main branch updates
**Options:**
- `git town sync` - Syncs current branch only
- `git town sync --stack` (or `-s`) - Syncs entire stack (use regularly to prevent phantom merge conflicts)
**Warning:** Don't use `--stack` on master - it will sync all branches

### `git town append <branch-name>`
**Purpose:** Create a child branch from current branch
**When to use:** When you need to build on top of current work
**Example:**
```bash
# On feature/user-auth branch
git town append feature/user-auth-tests
# Creates tests branch that depends on auth branch
```

### `git town prepend <branch-name>`
**Purpose:** Insert a new parent branch between current and its parent
**When to use:** When you realize you need foundational work before current branch
**Example:**
```bash
# On feature/user-auth branch (child of main)
git town prepend feature/auth-models
# Creates: main -> auth-models -> user-auth
```

### `git town propose --title "..." --body "..."`
**Purpose:** Create pull request for current branch
**Requires:** Both `--title` and `--body` flags — skips interactive TUI entirely
**Always follow with:**
```bash
gh pr edit --add-assignee @me --add-label <label>
```
**Why not `gh pr create`:** `git town propose` handles branch sync and stack breadcrumbs automatically.

---

## PR Style Guide

Derived from analysis of Jared's PRs written before May 2025 (pre-Claude). Always match this style exactly.

### Title Format

Exact template: `<TICKET_ID> (<type>) | <Verb phrase>`

- Ticket ID is a Linear issue number (`ENG-NNN`). Omit entirely if no ticket: `(fix) | Fix validation on breaks`
- Type tags (lowercase, parenthesised): `(fix)` `(hotfix)` `(feature)` `(migration)` `(internal)`
- Verb phrase: sentence case, imperative. E.g. `Apply country specific settings synchronously`
- Backtick-wrap code references in titles: `Fix N+1 in \`KeyAlert::SendAlertLogic\``
- No emoji in titles

### Body Structure

Always use this exact section order with `## Level-2 headers` and `<br/>` between every section:

```markdown
## Background

Plain-English summary of the problem being solved. Cause → investigation → decision.
Write for someone who hasn't read the ticket — summarise the issue clearly, don't say
"see ticket for background." Use `NOTE:` callouts inline for important constraints.

<br/>

## Features / Changes

- Each bullet is one distinct change the reviewer needs to know about — not an implementation step or sub-detail of a previous bullet
- If a change needs more explanation, add another sentence to the same bullet or use indented sub-bullets; don't split into separate top-level bullets
- The reviewer can read GitHub's diff for code specifics — this section explains
  *what the product/system now does differently* and why that matters
- Use backticks for code references when unavoidable: `ClassName`, `method_name`

<br/>

## Testing Tasks

- [x] Concrete manual QA steps through the browser with specific org/timesheet IDs where relevant
- [x] If hard to manually test: "Small change which is hard to manually test."

<br/>

## Screenshots

![image](...) or "None."
```

### Tone

- Conversational, first person: "I think", "I've found", "I'm happy with"
- Direct — state opinions plainly: "I think we should just get rid of it for now"
- Address the reviewer directly when uncertain: "FOR REVIEWERS: things I'm unsure on"
- Write how you'd explain it to a colleague, not a corporate document
- Background is prose paragraphs, not bullet points
- Section headers are always `##` or `###`, never `#`
- Bold only for link labels (`**Linear**`, `**Related PR:**`), not for emphasis in body text

---

### `git town set-parent <parent-branch>`
**Purpose:** Change which branch is the parent of current branch
**When to use:** Reorganizing stack structure or fixing dependencies
**Example:**
```bash
# Move current branch to depend on different parent
git town set-parent feature/new-parent
```


### Inserting Missing Foundation
```bash
# You're on feature/user-dashboard but realize you need auth first
git town prepend feature/authentication

# Now you have: main -> authentication -> user-dashboard
# Implement auth in the prepended branch
```

### Reorganizing Stack Dependencies
```bash
# Move current branch to depend on different parent
git town set-parent feature/shared-components

# Useful when stack structure needs adjustment
```

## Splitting Work into Stacked PRs

When you need to split existing work into multiple PRs (e.g., migration + feature), follow this general workflow:

### General Principle: Separate Commits First

**Always create logically separated commits BEFORE organizing branches.** This is key for automation-friendly workflows.

```bash
# 1. Create separate commits (most foundational first)
git add files/for/foundation
git commit -m "Foundation work (e.g., migration)"
# Note the commit SHA

git add files/for/feature
git commit -m "Feature implementation"
```

### Approach 1: Using Prepend (When Foundation is Discovered After)

Use when you realize existing work needs a foundation branch underneath:

```bash
# Current: main -> feature/full-work
git town prepend migration/foundation

# Cherry-pick foundation commit to new parent
git cherry-pick <foundation-commit-sha>

# Sync stack
git town sync -s

# Result: main -> migration/foundation -> feature/full-work
```

### Approach 2: Using Hack + Set-Parent (When Building From Scratch)

Use when you're planning the stack structure upfront:

```bash
# Create foundation branch first
git town hack migration/foundation
# Make foundation commits
git commit -m "Foundation work"

# Create feature branch from main (not foundation yet)
git checkout main
git town hack feature/implementation
# Make feature commits
git commit -m "Feature work"

# Set foundation as parent
git town set-parent migration/foundation

# Sync stack
git town sync -s

# Result: main -> migration/foundation -> feature/implementation
```

### Approach 3: Using Append (When Adding Follow-up Work)

Use when you want to add dependent work on top of existing branch:

```bash
# On existing feature branch
git town append feature/follow-up
# Make follow-up commits

# Result: main -> feature/existing -> feature/follow-up
```

### After Organizing: Create PRs

```bash
# Create PR for each branch in stack
git checkout migration/foundation
git town propose --title "..." --body "..."
gh pr edit --add-assignee @me --add-label <label>

git checkout feature/implementation
git town propose --title "..." --body "Depends on #<parent-pr>"
gh pr edit --add-assignee @me --add-label <label>
```

## ⛔ NEVER Manually Stash

**`git stash` is FORBIDDEN when using git town.** Git town automatically stashes and restores uncommitted changes for `hack`, `sync`, `append`, `prepend`, and all branch-switching commands. Running `git stash` manually before a git town command is redundant, creates extra stash entries, and complicates the workflow.

- ❌ `git stash` then `git town hack` — WRONG
- ✅ `git town hack feature/name` directly with dirty working directory — CORRECT

## Tips for Claude Code

- **Separate commits by concern BEFORE using git town commands** - this is essential for automation
- Use `prepend` when you discover missing prerequisites
- Use `append` to add dependent work on top
- Use `hack` + `set-parent` when planning stack structure upfront
- `set-parent` helps reorganize stack relationships after the fact
- Each branch in stack should have its own focused PR for easier review

## Git Workflow Rules

- **ALWAYS check current branch status before starting any feature work**
- **Include `git town hack feature/branch-name` as first step in implementation plans**
- Use git town for all branch management and stacked development
- Branch naming: feature/task-description or feature/task-id-description
- Standard workflow: 1) Check current branch, 2) Create feature branch, 3) Implement code, 4) Write tests, 5) Commit
- **`git town propose` syncs the branch automatically — no need to run `git town sync` before proposing**
- **Only run `git town sync` when explicitly asked to push**
- **NEVER use `git push` directly**
