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

Special tag: `+next` — boosts urgency by 15.0 (highest single factor). Use sparingly for true top priorities.

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

## Best Practices

- **Capture immediately** — `task add` with whatever you know, enrich later with `modify`
- **Decompose vague tasks** — "Renovate kitchen" is not a task, "Select floor tiles" is
- **Use `wait` to reduce clutter** — hide tasks not relevant this week
- **Review regularly** — delete stale tasks, correct metadata
- **Start tasks** — `task start` tracks what you're actively doing
- **Keep descriptions short** — they become Zellij tab names

## Zellij Integration

When inside Zellij, Taskwarrior hooks automatically:
- **`task start`** — Creates a new tab with nvim + claude + lazygit
- **`task done`/`task stop`** — Closes the current tab after a brief delay

The hook only fires when the `ZELLIJ` env var is set.

## Integration with Other Skills

- Use `/git-town` for branch creation aligned to the task
