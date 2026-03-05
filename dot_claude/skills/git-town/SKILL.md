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
| Take over someone's branch | `git town feature <branch>` | Full ownership: sync with parent + push |
| Contribute to someone's branch | `git town contribute <branch>` | Push your changes, but don't sync with parent |
| Watch someone's branch (read-only) | `git town observe <branch>` | Pull only, don't push |

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

## Working on Someone Else's Branch

When adopting an existing PR or working on a colleague's branch, use git town's branch type commands to control sync and push behaviour.

### Branch Types

| Type | `sync` pulls from remote? | `sync` syncs with parent? | `sync` pushes? | Use when... |
|------|--------------------------|--------------------------|----------------|-------------|
| `feature` (default) | Yes | Yes | Yes | You own the branch — full control |
| `contribute` | Yes | No | Yes | Collaborating — the other dev manages parent sync |
| `observe` | Yes | No | No | Read-only — just tracking their progress |

### Adopting a Stale/Abandoned PR

When a colleague has left or a PR went stale and you're taking over:

```bash
# 1. Fetch and checkout
git fetch origin <branch-name>
git checkout <branch-name>

# 2. Take full ownership (sync with parent + push)
git town feature <branch-name>

# 3. Sync to rebase onto current master — resolves conflicts
git town sync
# If conflicts: resolve them, then `git town continue`
```

Use `feature` here because the original author is no longer managing the branch — you need full sync with parent to resolve staleness.

### Contributing to an Active PR

When helping a colleague who is still actively working on their branch:

```bash
git fetch origin <branch-name>
git checkout <branch-name>

# Contribute mode: push your changes, but let them manage parent sync
git town contribute <branch-name>

git town sync   # pulls their latest changes, pushes yours, skips parent sync
```

Use `contribute` because the other dev is still responsible for rebasing onto parent.

### Reviewing a PR Locally (Read-Only)

When you just want to pull someone's branch to read/test locally without pushing:

```bash
git fetch origin <branch-name>
git checkout <branch-name>

# Observe mode: pull only, never push
git town observe <branch-name>

git town sync   # pulls their latest, doesn't push anything
```

### Switching Back to Default

To return a branch to normal feature behaviour:

```bash
git town feature <branch-name>
```

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

Always use `### Level-3 headers` and `<br/>` between every section, in this order:

```markdown
### Background
...
<br/>
### Features / Changes
...
<br/>
### Testing Tasks
...
<br/>
### Screenshots
...
```

### Background

- Start from the motivation: the reported problem (bug) or the product need (feature)
- Tell the story: what was observed or requested → what was investigated or designed → what this PR does about it
- Write for someone who hasn't read the ticket — summarise clearly, don't say "see ticket"
- Domain model names are fine when needed for clarity (e.g. `WageComparison`), but don't describe code mechanics or implementation details
- Prose paragraphs, not bullet points
- Use `NOTE:` callouts inline for important constraints

### Features / Changes

- Each bullet is one distinct behavioural change — what the system now does differently
- The reviewer reads the diff for implementation specifics — this section explains *what changed* and *why*, not *how*
- If an implementation detail needs reviewer attention, add it as an inline comment on the diff, not in the PR body
- Don't mix code snippets or method signatures with natural language

> **Wrong** (implementation-focused): Changed `allowance_tag_options` to accept the template as a kwarg instead of hardcoding `employment_condition_set_template`
>
> **Right** (behaviour-focused): The additional tags dropdown now correctly shows previously selected values when editing a position's wage comparison template

### Testing Tasks

- Concrete manual QA steps through the browser with specific org/timesheet IDs where relevant
- If hard to manually test: "Small change which is hard to manually test."

### Screenshots

`![image](...)` or "None."

### Tone

- Conversational, first person: "I think", "I've found", "I'm happy with"
- Direct — state opinions plainly: "I think we should just get rid of it for now"
- Address the reviewer directly when uncertain: "FOR REVIEWERS: things I'm unsure on"
- Write how you'd explain it to a colleague, not a corporate document
- Background is prose paragraphs, not bullet points
- Section headers are always `###`, never `#` or `##`
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
