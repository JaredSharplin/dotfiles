---
name: task
description: "PROACTIVE SKILL — Claude MUST load this skill automatically at the start of any work session, when asked to work on something, or when task management is relevant. Do NOT wait for the user to invoke /task. Triggers: session start, beginning work, creating PRs, finishing work, 'task', 'todo', 'what should I work on'."
---

# Taskwarrior — Personal Task Management

Taskwarrior (`task`) is the personal task management system. Tasks are the single source of truth for what's being worked on — they coordinate across sessions, tools, and branches.

Use `t` for start/done/stop (it handles Zellij tab renaming). Use `task` directly for everything else.

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
3. Start it: `t start <id>`
4. Annotate the approach: `task <id> annotate "Starting: <brief plan>"`

### Adding Tasks from User Requests

The description is just a short title — it is NOT the place for requirements.

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

1. After creating a draft PR: `task <id> annotate "PR: <url>"`
2. Self-review and manual QA the PR
3. Mark PR ready for review: `gh pr ready <number>`
4. Wait for the PR to be reviewed and merged
5. `t done <id>`

### Key Principle
Annotations are cheap. Annotate often. They create a trail that survives session boundaries and helps the next session pick up where things left off.

## `t` Command Reference

`t` is a thin wrapper around `task` that handles Zellij tab renaming.

| Command | What it does |
|---|---|
| `t start <id>` | Start a task, rename current Zellij tab to `"#<id> description"` |
| `t done <id>` | Mark task done, rename tab back to `"Slot N"` |
| `t stop <id>` | Stop task (stays pending), rename tab back |
| `t <anything>` | Passthrough to `task` binary (e.g. `t list`, `t next`, `t active`) |

## `task` Command Reference

### Core Commands

| Command | Description |
|---|---|
| `task add "desc"` | Create a task |
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
- **Start tasks** — `t start` tracks what you're actively doing
- **Keep descriptions short** — they become Zellij tab names

## Zellij Integration

The `workspace-payaus` layout pre-builds 6 slot tabs (Slot 1–6), each with a Claude pane, nvim, and lazygit. Slots map to worktree directories `~/programming/worktrees/slot-{1,2,3,4,5,6}`.

### Tab Lifecycle

| Event | Action |
|---|---|
| `t start <id>` | Renames current tab to `"#<id> description"` |
| `t done <id>` | Renames tab back to `"Slot N"` |
| `t stop <id>` | Renames tab back to `"Slot N"` |

If all 6 slots are occupied, navigate to a slot and stop its task first.

### zjstatus Bar

The status bar shows task counts and GitHub PR status:
- **active** (green): currently started tasks
- **Next** (yellow): next `+PENDING` task description (wide screens)
- **draft PRs** (orange): your open draft PRs
- **stale PRs** (red): your PRs labelled stale
- **queued** (blue): pending backlog count
- **on hold** (orange): waiting tasks count

## Monday Review

On session start, if today is Monday, Claude automatically runs a review:

1. **Check resurfaced tasks:** `task +WAITING list` — tasks with `wait:monday` reappear on Mondays
2. **Triage each resurfaced task:** Ask the user "Keep waiting or act on it?"
3. **Defer skipped tasks:** `task <id> modify wait:monday` to push back another week

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
| `sprint` | Current payaus sprint work | `project:payaus or project:payaus.internal` |

Switch contexts:
```bash
task context focus      # narrow to active work only
task context sprint     # see current sprint backlog
task context none       # clear context, see everything
```

## Integration with Other Skills

- Use `/git-town` for branch creation aligned to the task
