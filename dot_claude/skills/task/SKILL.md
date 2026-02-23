---
name: task
description: Use this skill for personal task management with Taskwarrior. Triggers include "task", "todo", "what should I work on", "create a task", "annotate task", or any task tracking operations. (user)
---

# Taskwarrior — Personal Task Management

Taskwarrior (`task`) is the personal task management system. Tasks are the coordination point between sessions — check for active tasks before starting work, annotate progress, and mark done when finished.

## Quick Reference

| If you want to... | Command | Notes |
|---|---|---|
| See current work | `task active` | Shows tasks with `start` set |
| See what's next | `task next` | Default view, sorted by urgency |
| Add a task | `task add "description"` | Add UDAs as needed |
| Start working on a task | `task <id> start` | Spawns Zellij tab if inside Zellij |
| Stop without finishing | `task <id> stop` | Closes Zellij tab |
| Mark done | `task <id> done` | Closes Zellij tab |
| Log progress | `task <id> annotate "message"` | Append a note to the task |
| View task details | `task <id> info` | Shows all fields + annotations |
| Export as JSON | `task export` | Machine-readable output |
| List by project | `task project:myproject list` | Filter by project |

## UDAs (User-Defined Attributes)

- **`project_dir`** — Filesystem path to the task's codebase. Used by the Zellij hook to set `--cwd` when spawning task tabs.

```bash
task add "Implement auth flow" project_dir:~/programming/payaus project:payaus
```

## Workflow: TTAL Pattern

Tasks are the coordination point. Follow this pattern:

### Starting a Session
1. Run `task active` to check if there's already work in progress
2. If yes, read annotations to understand where things left off
3. If no, run `task next` to pick the highest-urgency task
4. `task <id> start` to begin (this spawns a Zellij workspace tab)

### During Work
- `task <id> annotate "message"` to log decisions, findings, blockers
- Annotations create a trail that survives session boundaries
- Use `/git-town` skill for branch creation aligned to the task

### Finishing Work
- `task <id> annotate "summary of what was done"` before finishing
- `task <id> done` to mark complete (closes Zellij tab)
- Use `/handoff` skill if handing off to another session

## Zellij Integration

When inside Zellij, Taskwarrior hooks automatically:
- **`task start`** — Creates a new tab using `task-workspace.kdl` layout with nvim + claude + lazygit, `--cwd` set to `project_dir`
- **`task done`/`task stop`** — Closes the current tab after a brief delay

The hook only fires when the `ZELLIJ` env var is set. Outside Zellij, commands work normally without side effects.

## Tips

- Keep task descriptions short — they become Zellij tab names
- Always set `project_dir` so the workspace opens in the right directory
- Use `project:name` for grouping related tasks
- Annotations are cheap — annotate often, especially before stopping
- `task <id> modify` to change fields after creation
