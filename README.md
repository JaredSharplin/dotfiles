# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Quick Start

```bash
chezmoi init --apply https://github.com/jaredsharplin/dotfiles.git
```

## Platform Support

- **macOS** — Homebrew (`Brewfile`), zsh, Ghostty, Karabiner
- **Linux** — pacman/yay (Arch), bash, Hyprland, keyd

## What's Managed

| Tool | Config Path |
|------|------------|
| Neovim | `dot_config/nvim/` |
| Zellij | `dot_config/zellij/` |
| Claude Code | `dot_claude/` |
| Lazygit | `dot_config/lazygit/` |
| Git | `dot_config/git/` |
| Starship | (via Brewfile) |
| Taskwarrior | `dot_config/task/` |
| Ghostty (macOS) | `dot_config/ghostty/` |
| Hyprland (Linux) | `dot_config/hypr/` |
| keyd (Linux) | `etc/keyd/` |

## Zellij Layouts

- **`default.kdl`** — Terminal + Main (nvim/claude/lazygit) + Dotfiles tabs
- **`task-workspace.kdl`** — Spawned by Taskwarrior hooks per task (`task start`)
- **`server.kdl`** — Payaus dev server (tunnel/server/webpack/worker)

## Post-Install Steps

```bash
# Install npm dependencies for task scripts (mermaid-ascii etc.)
cd ~/.config/task && npm install
```

## Repo Structure

Chezmoi naming conventions:
- `dot_` prefix maps to `.` (e.g. `dot_zshrc` -> `~/.zshrc`)
- `.tmpl` suffix means the file is a Go template (platform conditionals)
- `executable_` prefix sets the executable bit
- `private_` prefix sets restrictive permissions
- `.chezmoiignore` controls which files are skipped per platform
- `.chezmoiscripts/` contains install scripts that run on `chezmoi apply`
