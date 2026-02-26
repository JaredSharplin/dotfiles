---
name: task
description: "PROACTIVE SKILL — Claude MUST load this skill automatically at the start of any work session, when asked to work on something, or when task management is relevant. Do NOT wait for the user to invoke /task. Triggers: session start, beginning work, creating PRs, finishing work, 'task', 'todo', 'what should I work on'."
---

# Taskwarrior — Personal Task Management

Taskwarrior (`task`) is the personal task management system. Tasks are the single source of truth for what's being worked on — they coordinate across sessions, tools, and branches.

## Proactive Behaviour (MANDATORY)

Claude MUST use Taskwarrior automatically as part of the development workflow:

### Session Start
1. Run `task active` to check for in-progress work
2. If a task exists: run `task <id> info` to read annotations — understand where things left off and suggest the next concrete step
3. If no active task: run `task next` to see what's queued — look for `+next` tagged task first
4. Check for Monday review (see below)

### When Starting Work
1. Check if a relevant task already exists: `task project:<name> list` or `task /keyword/ list`
2. If no task exists, create one: `task add "description" project:<name>`
3. If running inside a slot (detect from `$PWD` matching `slot-N`): `task <id> modify project_dir:$PWD` — this pins the task to the current slot instead of the hook picking the first free one
4. Start it: `task <id> start`
5. Annotate the approach: `task <id> annotate "Starting: <brief plan>"`

### Adding Tasks from User Requests

⛔ **The description is just a short title — it is NOT the place for requirements.**

When the user provides requirements, context, or detail while requesting a task:
1. Keep `task add "..."` short — it becomes the tab name and task title
2. **Immediately** follow with `task <id> annotate "Requirements: ..."` capturing the full detail the user gave
3. Do NOT wait to be asked — if the user gave you detail, annotate it straight away

### During Work — Annotate at Milestones
- `task <id> annotate "Branch: feature/..."` — after creating a branch
- `task <id> annotate "Decision: ..."` — significant design choices
- `task <id> annotate "Blocked: ..."` — when hitting a blocker
- `task <id> annotate "Tests passing"` — after tests go green
- `task <id> annotate "PR: <url>"` — after creating a pull request

### Finishing Work

⛔ **NEVER mark a task done until the PR is both reviewed AND merged.**

1. After creating PR: `task <id> annotate "PR: <url>"`
2. Exit the session — the loop auto-detects the PR annotation and chains walkthrough → review
3. Wait for the PR to be reviewed and merged
4. Verify `Self-reviewed:` annotation exists: `task <id> info`
5. `task <id> done`

### Key Principle
Annotations are cheap. Annotate often. They create a trail that survives session boundaries and helps the next session pick up where things left off.

## Command Reference

### Core Commands

| Command | Description |
|---|---|
| `task add "desc"` | Create a task |
| `task <id> start` | Mark as active (spawns Zellij tab) |
| `task <id> stop` | Deactivate without completing (closes Zellij tab) |
| `task <id> done` | Mark complete (closes Zellij tab) |
| `task <id> delete` | Delete a task |
| `task <id> modify "new desc" +tag` | Change attributes |
| `task <id> annotate "msg"` | Add a timestamped note |
| `task <id> denotate "msg"` | Remove an annotation |
| `task <id> info` | Full detail view with annotations |
| `task log "desc"` | Record an already-completed task |
| `task undo` | Revert the last change |

### Viewing Commands

| Command | Description |
|---|---|
| `task next` | Primary view — sorted by urgency |
| `task active` | Currently started tasks |
| `task ready` | Pending, not blocked, not waiting |
| `task project:<name> list` | Filter by project |
| `task +TAG list` | Filter by tag |
| `task /pattern/ list` | Regex search descriptions and annotations |

### En-Passant Modifications

Modify attributes while performing another action:
```bash
task <id> done project:payaus       # complete and change project
task <id> start +urgent             # start and add tag
```

## Task Structure

### Projects

Hierarchical grouping with dot notation:
```bash
task add "Fix auth" project:payaus
task add "Update docs" project:payaus.docs
task project:payaus list              # shows all sub-projects
```

### Tags

Tags go **outside** the quoted description, as separate arguments:
```bash
task add "Fix the leak" +backend +review
task +backend list                    # filter by tag
task -frontend list                   # exclude tag
task +TAGGED list                     # any task with at least one tag
```

**Tag names MUST use underscores, NEVER hyphens.** Hyphens are arithmetic operators in Taskwarrior filters — `+no-linear` is parsed as `+no` minus `linear` and will error.
```bash
# WRONG — hyphen breaks filter
task add "Fix bug" +no-linear         # creates broken tag
task +no-linear list                  # ERROR: Cannot subtract from Boolean

# RIGHT — underscore works
task add "Fix bug" +no_linear
task +no_linear list                  # filters correctly
```

Special tag: `+next` — exactly 1 task should carry this tag at any time. Marks the top priority when deciding what to work on next. Boosts urgency by 15.0 (highest single factor). This is not a constraint on parallelism — multiple tasks can be active simultaneously via parallel worktrees.

### Virtual Tags (for filtering)

| Tag | Meaning |
|---|---|
| `+ACTIVE` | Task has been started |
| `+BLOCKED` | Depends on incomplete task |
| `+BLOCKING` | Other tasks depend on this |
| `+READY` | Pending, not blocked, not waiting |
| `+ANNOTATED` | Has annotations |

### Dates

Use `scheduled` for "start after" and `wait` to hide tasks until relevant:
```bash
task add "Deploy feature" scheduled:monday
task add "Review Q2 report" wait:eom
```

Named dates: `today`, `tomorrow`, `monday`..`sunday`, `eow`, `eom`, `som`, `sow`, `later`/`someday`

## Shell Quoting Gotchas

When calling `task` from a shell (including Claude Code's Bash tool), quoting matters:

### Description is a bare quoted string — NOT `description:` attribute
```bash
# WRONG — description: attribute gets mangled by bash quoting
task 5 modify description:"Fix the bug" +urgent    # description becomes empty or wrong

# RIGHT — bare quoted string sets description
task 5 modify "Fix the bug" +urgent                 # description = "Fix the bug", tag = urgent
```

### Tags, projects, priority go OUTSIDE the quotes
```bash
# WRONG — tags in quotes become part of description text
task add "Fix the leak +backend +review"            # description = "Fix the leak +backend +review"

# RIGHT — tags as separate arguments
task add "Fix the leak" +backend +review project:payaus priority:M
```

### Multiple annotations need separate commands or `&&` chains
```bash
task 1 annotate "Linear: https://..." && task 1 annotate "PR: https://..." && task 1 annotate "Branch: feature/..."
```

### Bulk modifications require piped confirmation
When modifying multiple tasks at once, Taskwarrior prompts for confirmation interactively. In Claude Code's Bash tool, pipe `all` to confirm:
```bash
echo "all" | task +on_hold modify wait:monday
```
Do NOT use `rc.confirmation=off` — it doesn't suppress the prompt in non-interactive shells.

## Best Practices

- **Capture immediately** — `task add` with whatever you know, enrich later with `modify`
- **Decompose vague tasks** — "Renovate kitchen" is not a task, "Select floor tiles" is
- **Use `wait` to reduce clutter** — hide tasks not relevant this week
- **Review regularly** — delete stale tasks, correct metadata
- **Start tasks** — `task start` tracks what you're actively doing
- **Keep descriptions short** — they become Zellij tab names

## Zellij Integration

The `workspace-payaus` layout pre-builds 6 slot tabs (Slot 1–6), each with a suspended Claude pane, nvim, and lazygit. Slots map to worktree directories `~/programming/worktrees/slot-{1,2,3,4,5,6}`.

### Tab Lifecycle

| Event | Action |
|---|---|
| `task start` | Assigns first free slot, sets `project_dir` UDA, writes context file, renames "Slot N" → task description, switches focus |
| `task done`/`task stop` | Renames tab back to "Slot N", switches to Main, deletes context file |

Slots are freed implicitly — a slot is "free" when no `+ACTIVE` task has its `project_dir` pointing to it. Stopping then restarting a task reuses the same slot.

If all 6 slots are occupied, `task start` prints a warning and no tab switch occurs.

### Claude Pane

Each slot's Claude pane starts suspended. When activated:
- If a context file exists (`~/.local/share/task/context/<uuid>.json`), Claude launches in plan mode with the task description
- If no context file matches the working directory, Claude launches bare

Context files are written by the on-modify hook and deleted on task completion/stop.

### Outside Zellij

The hook still assigns a slot and writes context, but skips all Zellij commands. The `ZELLIJ` env var controls this.

## Monday Review (Automated)

On session start, if today is Monday (or if `task +WAITING` shows resurfaced tasks), Claude automatically runs a review:

1. **Check resurfaced tasks:** `task +WAITING list` — tasks with `wait:monday` reappear on Mondays
2. **Cross-reference PRs:** Run `gh pr list --author @me --state open` and compare with task annotations:
   - Mark tasks done only if their PR was reviewed AND merged (check `gh pr view <url> --json state,mergedAt,reviews` — `state` must be `MERGED`)
   - Annotate tasks if their PR has new review comments
   - Flag tasks whose PRs have been idle (no activity in 7+ days)
3. **Triage each resurfaced task:** Ask the user "Keep waiting or act on it?"
4. **Defer skipped tasks:** `task <id> modify wait:monday` to push back another week

### On-Hold Tasks

Tasks tagged `+on_hold` should be hidden from daily views using `wait`:
```bash
task +on_hold modify wait:monday
```
They resurface every Monday for review. After Monday triage, any that remain on hold get deferred again.

## Contexts

Two contexts are configured for focused work:

| Context | Purpose | Filter |
|---|---|---|
| `focus` | Only active and next-tagged work | `+ACTIVE or +next` |
| `sprint` | Current payaus sprint work, excluding on-hold | `project:payaus -on_hold -WAITING` |

Switch contexts:
```bash
task context focus      # narrow to active work only
task context sprint     # see current sprint backlog
task context none       # clear context, see everything
```

## Stale Task Detection

A task is **stale** when it's active (`+ACTIVE`) but has had no annotation in 24 hours. This indicates work that's started but idle — possibly forgotten across sessions.

The Zellij statusbar shows stale count in red when > 0. On seeing a stale warning:
1. Run `task +ACTIVE info` to check annotations
2. Either annotate with current status or stop the task if it's not being worked on

## PR Review Workflow

Slots are shared between tasks and PR reviews. Scripts manage the review lifecycle.

### `pr-review <number|url>`

Run from any terminal inside Zellij. Auto-detects whether you are the PR author:

- **Self-review** (you are the author): uses the current slot (branch already checked out),
  writes `review-slot-N.json` with `is_self_review: true`, renames tab `"Slot N: Self-review #N"`.
  Usually triggered automatically — after any implementation session exits, the loop checks
  for an unreviewed `PR:` annotation and calls `pr-review` itself. No manual step needed.

- **External review** (someone else's PR): finds a free slot, checks out the branch, writes
  `review-slot-N.json` with `is_self_review: false`, renames tab `"Slot N: Reviewing #N"`,
  then switches to that slot.

In both modes, `task-tab-claude.sh` runs two sessions in sequence:
1. **Walkthrough** — explains the diff file-by-file, pauses for questions at each file.
   If self-review, annotates the task with `Self-reviewed: <summary>` when you confirm understanding.
2. **Code review** — fetches the diff fresh as an independent reviewer, uses 37signals +
   ActiveRecord personalities, posts inline comments and a summary.

After both sessions complete, the review context file is deleted and the tab is renamed back.

### `pr-done`

Run from within an external review slot to abort a review early. Removes the `.pr-review`
marker and review context file, renames the tab back to "Slot N", and switches to Main.

### How Free Slots Are Detected

A slot is occupied if either:
- An `+ACTIVE` task has `project_dir` pointing to it
- A `.pr-review` marker file exists in the slot directory

The first slot that satisfies neither condition is assigned.

## Integration with Other Skills

- Use `/git-town` for branch creation aligned to the task
