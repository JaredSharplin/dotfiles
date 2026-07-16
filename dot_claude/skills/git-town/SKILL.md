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
| Create PR for current branch | `git town sync` then `gh pr create --draft --base <parent> ...` | Opens as a draft, assignee + labels inline — see "Creating a PR" |
| Push branch/stack to remote | `git town sync --push` | Pushing is off by default — see "Pushing (off by default)" |
| Switch to parent branch | `git town down` | Move down the stack |
| Switch to child branch | `git town up` | Move up the stack |
| Fix something on a parent branch | See "Making Changes on a Parent Branch" | Stash → down → fix → sync → up → pop → sync |
| Change parent-child relationships | `git town set-parent <branch>` | Reorganize stack structure |
| Take over someone's branch | `git town feature <branch>` | Full ownership: sync with parent + push |
| Contribute to someone's branch | `git town contribute <branch>` | Push your changes, but don't sync with parent |
| Watch someone's branch (read-only) | `git town observe <branch>` | Pull only, don't push |

## Pushing (off by default)

Pushing is **off by default** (`push-branches = false` in global git config). This is deliberate: routine syncs shouldn't burn Buildkite CI builds.

- `git town sync` (and `sync -s`) update branches **locally only** — they do **not** push to the remote.
- To push on purpose: **`git town sync --push`** (overrides the config for that run). Use `git town sync -s --push` to push the whole stack.
- `gh pr create --draft` pushes the branch as part of opening the PR — that's a new branch's first push. Because the PR opens as a draft, no CI runs; CI first runs when the PR is marked ready for review.
- `observe` branches never push regardless (they're read-only).

Rule of thumb: sync freely to stay up to date; push only when you actually want the remote / PR updated. Pushing a *draft* runs no CI (Buildkite skips drafts without the `run-bk` label) — CI runs when the PR is marked ready.

## When to Use Git Town vs Standard Git

**Use Git Town for:**
- Branch creation and hierarchy management (`hack`, `append`, `prepend`)
- Keeping stacks synchronized (`sync`) — also what writes PR stack-nav links
- Modifying stack relationships (`set-parent`)

(PRs are created with `gh pr create --draft` — see "Creating a PR".)

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

## ⛔ Suspended Command State — STOP, Don't Blind-Answer

A previous git town command (usually `sync`) that hit a conflict or was interrupted leaves **suspended runstate**. The next git town command then tries to prompt about it before doing anything — in an agent shell with no TTY this surfaces as `Error: could not open a new TTY: open /dev/tty: device not configured`.

**This is the suspended state, not an environment/TTY problem.** Don't misdiagnose it, and don't try to force the prompt through (`script`, `unbuffer`, `expect`) — git town reads `/dev/tty` directly, so `--non-interactive`, piping stdin, and `--dry-run` all fail identically.

Diagnose read-only (safe, won't prompt): `git town status`. Then **STOP and ask the user how to recover** — the options (`continue`, `skip`, `undo`, or `git town status reset`) include destructive ones, so the choice is theirs ([[feedback_no_unilateral_decisions]]).

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

# 4. Sync the parent branch (local only — does not push)
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
git town sync                                   # integrate parent locally; does NOT push
parent=$(git config "git-town-branch.$(git branch --show-current).parent")
gh pr create --draft --base "${parent:-master}" \
  --title "..." --body "..." \
  --assignee @me --label <type-label> --label built-in-australia
```

`git town sync` integrates the parent locally (no push); `gh pr create --draft` then pushes the branch and opens the PR **as a draft** in one step, assignee and labels inline. Opening as a draft keeps CI quiet from the start (Buildkite skips drafts — payaus #56255). `--base` resolves to the branch's git-town parent (`master` for an ordinary branch). (Git Town 23 can't open drafts, so `gh` handles creation.)

Stack navigation links (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`) are written by `git town sync`, so a `gh`-created PR gets them on the next sync of the stack. **Do NOT manually add "Depends on #123" or stack information to PR bodies** — git town manages this automatically. (Verify the links appear on your first stacked PR created this way.)

**Every PR starts as a draft** — *not yet self-reviewed or manually QA'd*, the QA gate. Marking a PR ready-for-review (`gh pr ready`) triggers its first CI run; Claude does this when the developer asks. Otherwise the draft stays put for the developer to QA.

## Working on Someone Else's Branch

When adopting an existing PR or working on a colleague's branch, use git town's branch type commands to control sync and push behaviour.

### Branch Types

| Type | `sync` pulls from remote? | `sync` syncs with parent? | `sync` pushes? | Use when... |
|------|--------------------------|--------------------------|----------------|-------------|
| `feature` (default) | Yes | Yes | Only with `--push` | You own the branch — full control |
| `contribute` | Yes | No | Only with `--push` | Collaborating — the other dev manages parent sync |
| `observe` | Yes | No | Never | Read-only — just tracking their progress |

The "`sync` pushes?" column reflects this setup's `push-branches = false`: plain `sync` never pushes for any type. For `feature`/`contribute`, add `--push` when you want to push; `observe` branches never push.

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

git town sync          # pulls their latest changes, skips parent sync (local only)
git town sync --push   # when you want to push your changes back to share them
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

### Length & Language (read this first)

These two rules override the urge to be thorough. PR bodies here are short and human, not exhaustive.

- **Short by default.** A reviewer should be able to read the whole body in under ~30 seconds. When in doubt, cut. The diff carries the detail — the body just frames it.
- **Plain English, like you'd explain it to a teammate out loud** — not architecture documentation. No engineering jargon or implementation vocabulary ("refactored", "extracted", "wired up", "leverages", "abstraction", "encapsulates"), and no class / method / file names in the body. Those belong in the diff or as inline review comments.
- **No padding.** Don't restate the title. Don't walk through the changes file-by-file or commit-by-commit. (Opening with "This PR adds…" / "This PR fixes…" is fine — leading with what it does beats easing in with context.)

If the body reads like a changelog of code edits, rewrite it as a couple of plain sentences about what changed for the user or the system.

### Title Format

Exact template: `<TICKET_ID> (<type>) | <Verb phrase>`

- Ticket ID is a Linear issue number (`ENG-NNN`). Omit entirely if no ticket: `(fix) | Fix validation on breaks`
- Type tags (lowercase, parenthesised): `(fix)` `(hotfix)` `(feature)` `(migration)` `(internal)`
- Verb phrase: sentence case, imperative. E.g. `Apply country specific settings synchronously`
- Backtick-wrap code references in titles: `Fix N+1 in \`KeyAlert::SendAlertLogic\``
- No emoji in titles

### Body Structure

Always use `### Level-3 headers` and `<br/>` between every section, in this order. **Put a blank line on both sides of every `<br/>`** — GitHub won't render the spacer or the following heading correctly if the `<br/>` is jammed against adjacent lines:

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

### A full body, before and after

The rules above are easy to nod along to and still miss. This is the target to match — same PR, written the wrong way then the right way.

**Wrong** — jargon, file-by-file walkthrough, lede buried under context:

```markdown
### Background
This is the fourth slice of the Manage Data Streams reshape. The previous slice
left a slot on the edit page. This PR wires up the chart component and refactors
the values table to read from the new `DataStream::Series` aggregation, extracting
the rendering logic into a shared presenter.

<br/>

### Features / Changes
- Refactored `DataStreamsController#edit` to instantiate the presenter
- Added `ChartComponent` and passed the series data through as a prop
- Extracted `values_table` partial to share markup with the show page
```

**Right** — leads with what it does, plain English, no code names:

```markdown
### Background
This PR adds a chart and a values table to the data stream edit page, so you can
see what a stream is actually producing without leaving the page. It's the fourth
slice of the Manage Data Streams reshape — the previous slice left a slot for it.

<br/>

### Features / Changes
- The edit page now shows a chart of the stream's recent values
- A values table sits below the chart so you can read the exact numbers

<br/>

### Manual Browser QA Tasks
- [ ] Open any data stream's edit page and confirm the chart renders with its recent values
- [ ] Check the values table below the chart matches what the chart is plotting
```

### Background

- **Lead with what the PR does.** The first sentence states the change in plain terms ("This PR adds a chart and values table to the data stream edit page…"). Motivation and context come *after*, not before — never make the reader wait for the lede.
- **2–4 sentences, one tight paragraph.** If you're describing how the code works, you've gone too far — cut back to the outcome and the motivation.
- After the lede: one or two sentences of context — the reported problem (bug), the product need (feature), or where this sits in a larger effort
- Write for someone who hasn't read the ticket — summarise clearly, don't say "see ticket"
- Domain model names are fine when needed for clarity (e.g. `WageComparison`), but don't describe code mechanics or implementation details
- Prose, not bullet points
- Use `NOTE:` callouts inline for important constraints

### Features / Changes

- A few short bullets, each one impactful change in plain user-facing terms — what the user or system now does differently
- Keep it short. A reviewer skimming the list should understand the PR's impact in seconds
- No code specifics — no method names, class names, file paths, parameter changes, or implementation details. The diff is right there
- If it reads like a changelog of code edits, rewrite it. If an implementation detail needs reviewer attention, add it as an inline comment on the diff, not in the PR body

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

Leave one placeholder per user-visible behaviour — bold heading + `_<!-- what to capture -->_`. After browser QA, capture the screenshots (see *Capturing during final QA*) and replace the placeholders with the uploaded images (see *Uploading to the PR*). Use "None." only for pure internal changes.

#### Capturing during final QA

When taking screenshots via Chrome DevTools MCP for the placeholders above, decide the final destination up front — don't dump them somewhere intermediate and reorganise later.

**Destination:** `~/Desktop/<branch-slug>-screenshots/`, where `<branch-slug>` is the current branch name with `/` replaced by `-` (so `feature/mds-v4-edit` → `feature-mds-v4-edit`). Per-branch subfolder is easy to drag from when filling in the PR body, and easy to delete after merge.

**Filenames:** slugify the screenshot prompt verbatim. A placeholder of `_<!-- Edit this week, daily view -->_` becomes `edit-this-week-daily.png`. Self-describing filenames let you match files to PR prompts by sight — no index, no guessing order.

**Workflow.** Chrome DevTools MCP's `take_screenshot` has a restrictive `filePath` allowlist that rejects `~/Desktop/...`, `$CLAUDE_JOB_DIR`, and most paths you'd want. The macOS system temp dir (`$TMPDIR`, resolves to `/var/folders/.../T/`) is always accepted and is the right intermediate.

`take_screenshot` takes a literal string, not a shell expression — so resolve `$TMPDIR` and the branch slug to concrete values *before* the screenshot call, then reuse them:

```bash
# Resolve once at the start of QA
TMP=$(echo -n "$TMPDIR")                            # e.g. /var/folders/zz/abc.../T/
SLUG=$(git branch --show-current | tr '/' '-')      # e.g. feature-mds-v4-edit
DEST="$HOME/Desktop/${SLUG}-screenshots"
mkdir -p "$DEST"
echo "TMP=$TMP  DEST=$DEST"                         # capture the resolved values
```

Then per screenshot, using the resolved literals:

```
take_screenshot filePath=/var/folders/zz/abc.../T/edit-this-week-daily.png
```

```bash
mv /var/folders/zz/abc.../T/edit-this-week-daily.png \
   /Users/<you>/Desktop/feature-mds-v4-edit-screenshots/edit-this-week-daily.png
```

**Never `cd` to do the move.** `cd` mutates persistent cwd, and downstream `git` / `gh` commands then silently target the wrong repo. `mv` with absolute paths doesn't need a cwd change.

Don't use any repo's `tmp/` directory as an intermediate — it leaves stray files in the repo and forces a later move anyway. System temp → final destination, one move.

#### Uploading to the PR

Upload the captured screenshots with the `gh image` extension — it prints paste-ready markdown, one line per file:

```bash
gh image ~/Desktop/<branch-slug>-screenshots/*.png
# → ![edit-this-week-daily.png](https://github.com/user-attachments/assets/<uuid>)
```

Drop those lines as a single block under the `### Screenshots` heading, replacing the placeholder(s), via the surgical body edit in *⛔ Editing PR Bodies* below.

`gh image` authenticates from your browser's `github.com` session (no PAT). If it reports being logged out, sign into GitHub in the browser and retry.

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
# Create a PR for each branch in stack (each opens as a draft — see "Creating a PR")
git town sync   # local sync of the whole state before creating PRs

git checkout migration/foundation
gh pr create --draft --base "$(git config git-town-branch.migration/foundation.parent)" \
  --title "..." --body "..." --assignee @me --label <type-label> --label built-in-australia

git checkout feature/implementation
gh pr create --draft --base "$(git config git-town-branch.feature/implementation.parent)" \
  --title "..." --body "..." --assignee @me --label <type-label> --label built-in-australia
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
- **Create PRs with `gh pr create --draft` after `git town sync` — opens as a draft, CI stays quiet.**
- **`git town sync` does NOT push (pushing is off by default) — push deliberately with `git town sync --push`; `gh pr create` pushes the branch as it opens the PR**
- **NEVER use `git push` directly**
