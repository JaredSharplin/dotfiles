---
name: git-town
description: Use this skill when working with git branches, creating PRs, or managing stacked changes. Triggers include "create branch", "new feature branch", "git town", "stacked PR", "split PR", "rebase", "resolve conflicts", "checkout branch", "adopt PR", "work on someone's PR", "merge conflicts", "make a pr", "create a pr", "open a pr", or any branch management operations. MUST be loaded before any `gh pr create`, `gh pr edit`, `git town sync`, `git checkout`, `git rebase`, `git push`, `git stash`, `git clone`, or branch switching operation. (user)
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
| Create PR for current branch | `git town propose --title ... --body ...` | Then `gh pr edit` to add assignee + labels |
| Switch to parent branch | `git town down` | Move down the stack |
| Switch to child branch | `git town up` | Move up the stack |
| Fix something on a parent branch | See "Making Changes on a Parent Branch" | Stash → down → fix → sync → up → pop → sync |
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
- `git town sync --stack` (or `-s`) - Syncs entire stack. **Use this whenever there's more than one branch in the stack** (current branch has a parent other than master, or has children). Plain `sync` on a stacked branch leaves siblings/descendants stale and produces phantom merge conflicts.
- `git town sync` - Syncs current branch only. Use only for a lone branch off master with no children.
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

### Navigating a Branch Stack

Use `git town down` and `git town up` to move between branches in a stack:

| Command | Purpose |
|---------|---------|
| `git town down` | Switch to the parent branch (move down the stack) |
| `git town up` | Switch to the child branch (move up the stack) |

For non-adjacent branches (e.g. jumping from grandchild to grandparent), use `git checkout <branch-name>` directly.

**Note:** `git town switch` exists but is an interactive TUI — Claude cannot use it.

**Important:** `git town down`/`up` do NOT auto-stash uncommitted changes. They are thin wrappers around `git checkout`. Uncommitted changes either carry over (if non-conflicting) or cause the command to fail. See "Making Changes on a Parent Branch" for the safe workflow.

### Making Changes on a Parent Branch

When you're working on a child branch and need to make a fix on a parent branch:

```bash
# 1. Stash any uncommitted changes on the child branch
git stash

# 2. Switch to the parent branch
git town down

# 3. Make your changes and commit
git add <specific files>
git commit -m "Fix description"

# 4. Sync the parent branch (pushes changes)
git town sync

# 5. Switch back to the child branch
git town up

# 6. Restore your uncommitted changes
git stash pop

# 7. Sync the child branch (merges parent changes into child automatically)
git town sync
```

**Why stash here?** Without stashing, uncommitted child-branch changes carry over to the parent's working tree. This is dangerous because:
- `git add .` would accidentally commit child-branch work on the parent
- If the same file has both child WIP and needs a parent fix, there's no way to selectively stage (Claude can't use interactive `git add -p`)

This is the **one exception** to the "never manually stash" rule — `git town down`/`up` don't auto-stash like `hack`/`sync`/`append` do.

**Shortcut:** After step 4, `git town sync --stack` syncs all descendants too, so you could skip step 7 — but you still need to `git town up` and `git stash pop` to get back to your child branch.

### Creating a PR

```bash
git town propose --title "..." --body "..."
gh pr edit --add-assignee @me --add-label <type-label> --add-label built-in-australia
```

`git town propose` syncs the branch (pushing it) and opens the PR in one step. It also automatically adds stack navigation links to the PR body (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`). **Do NOT manually add "Depends on #123" or stack information to PR bodies** — git town manages this automatically.

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
### Manual Browser QA Tasks
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

- Each bullet is one impactful change described in general terms — what the user or system now does differently
- Keep it short. A reviewer skimming the list should understand the PR's impact in seconds
- No code specifics — no method names, class names, file paths, parameter changes, or implementation details. The diff is right there
- If an implementation detail needs reviewer attention, add it as an inline comment on the diff, not in the PR body

> **Wrong**: Changed `allowance_tag_options` to accept the template as a kwarg instead of hardcoding `employment_condition_set_template`
>
> **Wrong**: Refactored the `WageComparison` model to use `find_by` with a composite key lookup on `award_id` and `level`
>
> **Right**: The additional tags dropdown now correctly shows previously selected values when editing a wage comparison template
>
> **Right**: Fixed duplicate wage comparison rows appearing when the same award level is assigned twice

### Manual Browser QA Tasks

This section is step-by-step instructions for a reviewer to manually verify the change in a browser. It is NOT a place to describe automated tests or what you did during development. Each task MUST be a markdown checkbox (`- [ ]`).

- Format every task as a checkbox: `- [ ] Navigate to Settings > Permissions and verify...`
- Describe how a reviewer can verify this change through the browser — navigate to the page, perform the action, check the result
- Think about the user journey: what does a human do to trigger this code path? That's your QA task
- For bug fixes: reproduce using the actual reported data — reference the org ID, user, and steps from the Linear ticket. The reviewer should be able to follow the original reproduction steps and confirm the bug is fixed
- NEVER include `bin/rails test`, automated test results, or descriptions of test coverage — that's what CI is for
- NEVER write "Small change which is hard to manually test." — think through the user journey and describe it. Every change that touches code a user can trigger is testable through the browser. The only exception is a pure internal refactor with zero UI effect (e.g. renaming a private method, changing a log format) — and even then, describe what you'd check to confirm nothing broke

### Screenshots

Leave one placeholder per user-visible behaviour — bold heading + `_<!-- what to capture -->_`. The author replaces each with `![image](...)` after browser QA. Use "None." only for pure internal changes.

### Tone

- Conversational, first person: "I think", "I've found", "I'm happy with"
- Direct — state opinions plainly: "I think we should just get rid of it for now"
- Address the reviewer directly when uncertain: "FOR REVIEWERS: things I'm unsure on"
- Write how you'd explain it to a colleague, not a corporate document
- Background is prose paragraphs, not bullet points
- Section headers are always `###`, never `#` or `##`
- Bold only for link labels (`**Linear**`, `**Related PR:**`), not for emphasis in body text

---

## ⛔ Editing PR Bodies

**`gh pr edit --body "full replacement"` is FORBIDDEN** — same severity as `git push --force`. It destroys checked checkboxes (`[x]` → `[ ]`), manually added notes, and any reviewer edits.

### Required Workflow

```bash
# 1. Fetch current body
body=$(gh pr view <number> --json body -q '.body')

# 2. Make surgical edits with Ruby
updated_body=$(ruby -e '
  body = ARGF.read
  # Insert, replace, or append — never wholesale replace
  body.sub!("## Changes", "## Changes\n- New bullet point")
  print body
' <<< "$body")

# 3. Write back
gh pr edit <number> --body "$updated_body"
```

### Rules

- **Always fetch the current body first** — never assume you know what's there
- **Surgical edits only** — insert, append, or replace specific sections. Never rewrite the full body
- **Preserve user state** — checked checkboxes (`[x]`), manually added notes, reviewer comments in the body
- **Leave `<!-- branch-stack-start -->` / `<!-- branch-stack-end -->` blocks alone** — git town manages these

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
# Create a PR for each branch in stack
git checkout migration/foundation
git town propose --title "..." --body "..."
gh pr edit --add-assignee @me --add-label <type-label> --add-label built-in-australia

git checkout feature/implementation
git town propose --title "..." --body "..."
gh pr edit --add-assignee @me --add-label <type-label> --add-label built-in-australia
```

## ⛔ NEVER Manually Stash (With One Exception)

**`git stash` is FORBIDDEN when using git town commands that auto-stash.** Git town automatically stashes and restores uncommitted changes for `hack`, `sync`, `append`, `prepend`, and all branch-switching commands. Running `git stash` manually before these commands is redundant, creates extra stash entries, and complicates the workflow.

- ❌ `git stash` then `git town hack` — WRONG
- ✅ `git town hack feature/name` directly with dirty working directory — CORRECT

**Exception:** `git town down`/`up` do NOT auto-stash (they're thin `git checkout` wrappers). When switching to a parent branch to make a fix, stash first to avoid cross-contaminating branches:

- ✅ `git stash` → `git town down` → fix → `git town up` → `git stash pop` — CORRECT
- ❌ `git town down` with uncommitted changes then `git add .` on parent — WRONG (commits child work on parent)

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
