# Agents

This is a [chezmoi](https://www.chezmoi.io/)-managed dotfiles repository. Source files here are templates that deploy to `$HOME`.

## Development Workflow Architecture

The dotfiles implement a slot-based parallel development workflow using Zellij, Taskwarrior, and git worktrees.

### Core Concept

6 **slots** (persistent worktree directories at `~/programming/worktrees/slot-{1..6}`) serve as parallel workspaces. Each slot can hold either an active **task** or a **PR review** at any time. Slots are managed automatically — `task start` and `pr-review` find the first free slot.

### Session Startup

The `workspace` shell function (in `dot_zshrc`) launches or reattaches a Zellij session using a layout file. It picks `workspace-payaus.kdl` if inside a payaus directory, otherwise `workspace.kdl`. Both layouts define:

- **Main tab** — Claude + nvim/lazygit/taskwarrior-tui stack
- **Slot 1–6 tabs** — each with a suspended Claude pane, nvim, and lazygit, rooted at their worktree directory
- **Dotfiles tab** — Claude session for this repo
- **zjstatus bar** — tabs on left, task totals + session + datetime on right

The payaus layout also has a **Server tab** for tunnel/server/webpack/worker. The `dev-server` function recreates this tab dynamically using `server.kdl`.

### Task Lifecycle

| Step | What happens |
|------|-------------|
| `task start <id>` | On-modify hook assigns first free slot, sets `project_dir` UDA, writes context JSON to `~/.local/share/task/context/<uuid>.json`, renames tab to `"Slot N: #<id> <description>"`, switches focus |
| Work in slot | Claude pane reads context file on activation, launches with task prompt. Annotate milestones with `task <id> annotate "..."` |
| `task done <id>` | Hook deletes context file, renames tab back to `"Slot N"`, switches to Main |
| `task stop <id>` | Same cleanup as done, but task stays pending |
| `task <id> annotate "Ready for peer review: <summary>"` | After addressing self-review findings and completing QA; clears pipeline nag; signals PR is ready to assign to a reviewer |

### PR Review Lifecycle

| Step | What happens |
|------|-------------|
| `pr-review <number\|url>` | Finds free slot, checks out PR branch in worktree, writes `.pr-review` marker + review context JSON, renames tab to `"Slot N: Reviewing <number>"` |
| Review in slot | nvim `<leader>gr` for diff picker, Claude pane activates with review prompt, lazygit for commit history |
| `pr-done` | Removes marker + context file, renames tab to `"Slot N"`, switches to Main |

### Free Slot Detection

A slot is **occupied** if either:
- An `+ACTIVE` task has `project_dir` pointing to it
- A `.pr-review` marker file exists in the slot directory

The first slot satisfying neither condition is assigned.

### Key Scripts (deployed to `~/.config/task/scripts/`)

| Script | Purpose |
|--------|---------|
| `on-modify.zellij` | Taskwarrior hook — slot assignment, context file management, tab renaming on task start/stop/done |
| `task-tab-claude.sh` | Reads context files, launches Claude with task or review prompt |
| `slot-rename-tab` | Renames a Zellij tab based on review context, task context, or idle state |
| `zjstatus-task-check.sh` | Generates statusbar output: stale (red), active (green), next (yellow), pending (blue), on-hold (orange) |
| `pr-review` | Opens a PR for review in a free slot |
| `pr-done` | Cleans up a review slot |

### Context Files (`~/.local/share/task/context/`)

- **Task context:** `<uuid>.json` — contains id, description, project, tags, annotations, project_dir
- **Review context:** `review-slot-<N>.json` — contains pr_number, title, author, url, project_dir

These files are the bridge between Taskwarrior/scripts and the Claude panes.

### Finishing a Task (PR approved and merged)

1. `gh pr merge <number> --squash --delete-branch`
2. `git town sync` (cleans up local branch)
3. `task done <id>` (frees the slot)

### zjstatus (Zellij Status Bar)

Configured in workspace layout files. Uses the [zjstatus](https://github.com/dj95/zjstatus) WASM plugin with gruvbox-dark colors. Tab dividers use dim gray (`#665c54`). Task totals are displayed on the right via `command_task` running `zjstatus-task-check.sh` every 300s. Claude Code session status is piped via `pipe_status`.

## Chezmoi Naming Conventions

| Prefix/Suffix | Meaning | Example |
|---------------|---------|---------|
| `dot_` | Maps to `.` | `dot_zshrc` -> `~/.zshrc` |
| `.tmpl` | Go template (conditionals) | `config.tmpl` -> rendered `config` |
| `executable_` | Sets executable bit | `executable_on-modify.zellij` |
| `private_` | Sets `0600` permissions | `private_secrets` |

## Platform Conditionals

Templates use `{{ .chezmoi.os }}` for platform-specific content:
- `darwin` = macOS
- `linux` = Linux (Arch)

Platform-specific files are excluded via `.chezmoiignore`.

## Adding a New Tool Config

1. Create the source file with chezmoi prefixes: `dot_config/toolname/config`
2. If platform-specific, add `.tmpl` suffix and use Go template conditionals
3. If the target should be excluded on some platforms, add to `.chezmoiignore`
4. Run `chezmoi diff` to preview, then `chezmoi apply` to deploy

## Conventions

- Theme: gruvbox-dark everywhere (terminal, editor, status bar)
- Keybindings: vim-style navigation
- Paths: XDG-compliant (`~/.config/`, `~/.local/share/`)
- Shell: zsh on macOS, bash on Linux
- Package management: Homebrew on macOS, pacman/yay on Linux

## Testing Changes

```bash
chezmoi diff          # Preview what would change
chezmoi apply -v      # Apply with verbose output
chezmoi apply -n      # Dry run (no changes)
```

**After editing any source file, always run `chezmoi apply` to deploy the changes to `$HOME`.**

### One-time setup (after first `chezmoi apply` on macOS)

```bash
# Load the PR pipeline nag launchd agent:
launchctl load ~/Library/LaunchAgents/com.jaredsharplin.pr-pipeline-nag.plist
```
