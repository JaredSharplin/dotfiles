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
2. If a task exists: run `task <id> info` to read annotations and understand context
3. If no active task: run `task next` to see what's queued

### When Starting Work
1. Check if a relevant task already exists: `task project:<name> list` or `task /keyword/ list`
2. If no task exists, create one: `task add "description" project:<name>`
3. Start it: `task <id> start`
4. Annotate the approach: `task <id> annotate "Starting: <brief plan>"`

### During Work — Annotate at Milestones
- `task <id> annotate "Branch: feature/..."` — after creating a branch
- `task <id> annotate "Decision: ..."` — significant design choices
- `task <id> annotate "Blocked: ..."` — when hitting a blocker
- `task <id> annotate "Tests passing"` — after tests go green
- `task <id> annotate "PR: <url>"` — after creating a pull request

### Finishing Work
1. `task <id> annotate "Done: <summary>"` — what was accomplished
2. `task <id> done` — mark complete

### Key Principle
Annotations are cheap. Annotate often. They create a trail that survives session boundaries and helps the next session (or the next Claude) pick up where things left off.

## Command Reference

### Core Commands

| Command | Description |
|---|---|
| `task add "desc"` | Create a task |
| `task <id> start` | Mark as active (spawns Zellij tab) |
| `task <id> stop` | Deactivate without completing (closes Zellij tab) |
| `task <id> done` | Mark complete (closes Zellij tab) |
| `task <id> delete` | Delete a task |
| `task <id> modify key:value` | Change attributes |
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
| `task ready` | Pending, not blocked, not waiting, not future-scheduled |
| `task blocked` | Tasks waiting on dependencies |
| `task blocking` | Tasks that block others |
| `task waiting` | Tasks hidden until their wait date |
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

### Attributes

| Attribute | Usage |
|---|---|
| `project` | Hierarchical grouping: `project:payaus`, `project:Home.Kitchen` |
| `priority` | `H` (high), `M` (medium), `L` (low), or empty |
| `tags` | `+tag` to add, `-tag` to remove: `task add Fix bug +urgent +backend` |
| `due` | Hard deadline ONLY — do not use for "when I want to start" |
| `scheduled` | Earliest date to begin work — task becomes `+READY` when this passes |
| `wait` | Hides task from views until this date: `wait:monday` |
| `until` | Auto-deletes task on this date (for time-sensitive items) |
| `depends` | Blocking relationship: `depends:<id>` or `depends:<id>,<id>` |

### Date Handling

Named dates: `today`, `tomorrow`, `yesterday`, `monday`..`sunday`, `eow` (end of week), `eom` (end of month), `eoy` (end of year), `som` (start of month), `sow` (start of week), `later`/`someday`

Relative: `due:today+3d`, `wait:due-2days`, `scheduled:monday`

Verify a named date: `task calc eow`

### Tags

Regular tags: `+urgent`, `+backend`, `+review`

Special behaviour tags:
- `+next` — urgency boost of 15.0 (highest single factor). Use sparingly for true top priorities
- `+nocolor` — disables color rules
- `+nonag` — suppresses overdue nagging

### Virtual Tags (for filtering)

| Tag | Meaning |
|---|---|
| `+ACTIVE` | Task has been started |
| `+BLOCKED` | Depends on incomplete task |
| `+BLOCKING` | Other tasks depend on this |
| `+READY` | Pending, not blocked/waiting/future-scheduled |
| `+OVERDUE` | Past due date |
| `+DUETODAY` | Due today |
| `+TAGGED` | Has at least one tag |
| `+ANNOTATED` | Has annotations |
| `+WAITING` | Hidden until wait date |

### Dependencies

```bash
task add "Write migration" project:payaus
task add "Update model" project:payaus depends:1
```

- Blocked tasks get urgency penalty (-5.0)
- Blocking tasks get urgency boost (+8.0)

### Projects

Dot-notation hierarchy:
```bash
task add project:Home.Kitchen "Fix tap"
task project:Home list          # shows all sub-projects
```

## Urgency System

Tasks are sorted by urgency in the `next` report. Key factors:

| Factor | Coefficient |
|---|---|
| `+next` tag | 15.0 |
| Due date (proximity) | 12.0 |
| Blocking other tasks | 8.0 |
| Priority H | 6.0 |
| Scheduled (past) | 5.0 |
| Active (started) | 4.0 |
| Priority M | 3.9 |
| Age | 2.0 |
| Priority L | 1.8 |
| Waiting | -3.0 |
| Blocked | -5.0 |

The `+next` tag is the strongest lever — use it to surface your true top priority.

## Best Practices

### Do
- **Capture immediately** — `task add` with whatever you know, enrich later with `modify`
- **Decompose vague tasks** — "Renovate kitchen" becomes "Select floor tiles", "Get contractor quotes"
- **Use `due` only for real deadlines** — fake deadlines create noise
- **Use `scheduled` for "start after"** — not `due`
- **Use `wait` to reduce clutter** — hide tasks not relevant this week
- **Review regularly** — delete stale tasks, correct metadata
- **Start tasks** — `task start` tracks what you're actively doing

### Don't
- Set `due` on everything (creates constant reorganisation burden)
- Create vague tasks that can never be "done"
- Ignore the list (if you don't look at it, it has no value)
- Over-engineer urgency coefficients
- Use too many tags (keep them consistent and sparse)

## Zellij Integration

When inside Zellij, Taskwarrior hooks automatically:
- **`task start`** — Creates a new tab using `task-workspace.kdl` layout with nvim + claude + lazygit
- **`task done`/`task stop`** — Closes the current tab after a brief delay

The hook only fires when the `ZELLIJ` env var is set. Outside Zellij, commands work normally.

## Integration with Other Skills

- Use `/git-town` for branch creation aligned to the task
- Use `/handoff` for session context transfer — annotate the task first
