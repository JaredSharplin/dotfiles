---
name: git-town
description: Use this skill when working with git branches, creating PRs, or managing stacked changes. Triggers include "create branch", "new feature branch", "git town", "stacked PR", "split PR", or any branch management operations. (user)
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
| Create PR for current branch | `git town propose` | Opens browser to create PR |
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

### `git town propose`
**Purpose:** Create pull request for current branch
**When to use:** When branch is ready for review
**Key benefit:** Automatically pushes branch and opens PR creation page

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
gh pr create --title "..." --body "..."

git checkout feature/implementation
gh pr create --title "..." --body "Depends on #<parent-pr>"
```

## Tips for Claude Code

- Always run `git town sync` before major operations to keep stack current
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
- **ALWAYS use `git town sync` instead of `git push` for pushing changes**
- **NEVER use `git push` directly - always use `git town sync` to maintain stack integrity**
