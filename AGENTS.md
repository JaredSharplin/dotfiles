# Agents

This is a [chezmoi](https://www.chezmoi.io/)-managed dotfiles repository. Source files here are templates that deploy to `$HOME`.

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
