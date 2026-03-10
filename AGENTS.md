# Agents

This is a [chezmoi](https://www.chezmoi.io/)-managed dotfiles repository. Source files here are templates that deploy to `$HOME`.

## Development Workflow Architecture

The dotfiles implement a slot-based parallel development workflow using Zellij, Taskwarrior, and git worktrees.

### Core Concept

6 **slots** (persistent worktree directories at `~/programming/worktrees/slot-{1..6}`) serve as parallel workspaces. Each slot can hold an active task at any time.

### Session Startup

The `workspace` shell function (in `dot_zshrc`) launches or reattaches a Zellij session using a layout file. It picks `workspace-payaus.kdl` if inside a payaus directory, otherwise `workspace.kdl`. Both layouts define:

- **Main tab** — Claude + nvim/lazygit/taskwarrior-tui stack
- **Slot 1–6 tabs** — each with a Claude pane, nvim, and lazygit, rooted at their worktree directory
- **Dotfiles tab** — Claude session for this repo
- **zjstatus bar** — tabs on left, task totals + PR status + session + datetime on right

The payaus layout also has a **Server tab** for tunnel/server/webpack/worker. The `dev-server` function recreates this tab dynamically using `server.kdl`.

### Task Lifecycle

| Step | What happens |
|------|-------------|
| `t start <id>` | Starts the task and renames the current Zellij tab to `"#<id> <description>"` |
| Work in slot | Claude pane for implementation. Annotate milestones with `task <id> annotate "..."` |
| `t done <id>` | Marks task complete, renames tab back to `"Slot N"` |
| `t stop <id>` | Same as done but task stays pending |

### Key Scripts (deployed to `~/.config/task/scripts/`)

| Script | Purpose |
|--------|---------|
| `t` | Thin task wrapper — start/done/stop with Zellij tab renaming, everything else passes through to `task` |
| `task-sync` | Syncs tasks with Linear issues and GitHub PRs — creates tasks from assignments, marks merged PRs done |
| `zjstatus-task-check` | Generates statusbar output: active tasks, draft/stale PRs, queued tasks, on-hold counts |

### PR Workflow

All PRs start as drafts. GitHub is the source of truth for PR status:
- **Draft** = work in progress, not yet self-reviewed or QA'd
- **Ready for review** = self-reviewed and manually QA'd, ready for peer review

The zjstatus bar shows draft and stale PR counts as a passive awareness indicator.

### Finishing a Task (PR approved and merged)

1. `gh pr merge <number> --squash --delete-branch`
2. `git town sync` (cleans up local branch)
3. `t done <id>`

### zjstatus (Zellij Status Bar)

Configured in workspace layout files. Uses the [zjstatus](https://github.com/dj95/zjstatus) WASM plugin with gruvbox-dark colors. Tab dividers use dim gray (`#665c54`). Task and PR status is displayed on the right via `command_task` running `zjstatus-task-check` every 300s. Claude Code session status is piped via `pipe_status`.

## Chezmoi Naming Conventions

| Prefix/Suffix | Meaning | Example |
|---------------|---------|---------|
| `dot_` | Maps to `.` | `dot_zshrc` -> `~/.zshrc` |
| `.tmpl` | Go template (conditionals) | `config.tmpl` -> rendered `config` |
| `executable_` | Sets executable bit | `executable_t` |
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

**Always edit chezmoi source files in `~/.local/share/chezmoi/`. Never edit deployed files directly.**

If given a home-directory path (e.g. `~/.claude/skills/foo/SKILL.md`), resolve it to the source first:

```bash
chezmoi source-path ~/.claude/skills/foo/SKILL.md
# → /Users/jaredsharplin/.local/share/chezmoi/dot_claude/skills/foo/SKILL.md
```

Edit the source path, then apply:

**After editing any source file, always run `chezmoi apply` to deploy the changes to `$HOME`.**
