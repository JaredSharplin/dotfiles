# Dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Quick Start

```bash
chezmoi init --apply https://github.com/jaredsharplin/dotfiles.git
```

### After the first apply

Two things `chezmoi apply` cannot do for you:

- **`~/.secrets`** — sourced by `.zshrc`, deliberately untracked. payaus reads `ANTHROPIC_API_KEY`
  from it with a bare `ENV.fetch` (`app/api_clients/large_language_model/client.rb`), so without it
  `db:setup` fails part-way through seeding the demo org.
- **Karabiner** — install the cask, launch it once so it writes a default profile, quit it, then
  apply. It rewrites `karabiner.json` on quit, so applying while it runs loses the change.

## Setting up payaus

`bin/native/ensure_running.sh` installs and starts puma-dev, memcached, mailpit and MinIO. It does
**not** install Ruby, Node, yarn or Postgres — `ruby.pp`, `node.pp` and `postgresql.pp` only check
for them and exit 1 if they are absent. Those come from here: the `Brewfile` and
`dot_config/mise/config.toml`, so apply these dotfiles first.

Homebrew 7 needs both of payaus's third-party taps trusted before the script runs, or it fails on
them. `install-homebrew.sh` handles this repo's own taps, not payaus's:

```bash
brew trust --tap puma/puma                          # puma_dev.pp taps before it trusts, so the tap fails
brew trust --cask puppetlabs/puppet/puppet-agent    # installed untrusted, so brew warns on every command after
```

Two more things that bite on a fresh machine:

- **Don't run payaus's `bin/setup`.** It appends `eval "$(mise activate zsh)"` to `~/.zshrc`, which
  both contradicts the shims-over-activate reasoning in `.zprofile` and drifts a managed file. Its
  useful parts are `brew bundle` and `mise install`, which you can run directly.
- **The run exits 6 regardless**, on MinIO's `mc alias` step — `mc` and `minio` both segfault on
  Apple silicon (`go-m1cpu`), and there is no fixed build published. Everything before it applies,
  so `.pumaenv`, `.native.env` and the puma-dev symlink are written; `bundle install` and
  `yarn install` are skipped and need running by hand.

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
| Ghostty (macOS) | `dot_config/ghostty/` |
| Hyprland (Linux) | `dot_config/hypr/` |
| keyd (Linux) | `etc/keyd/` |

## Repo Structure

Chezmoi naming conventions:
- `dot_` prefix maps to `.` (e.g. `dot_zshrc` -> `~/.zshrc`)
- `.tmpl` suffix means the file is a Go template (platform conditionals)
- `executable_` prefix sets the executable bit
- `private_` prefix sets restrictive permissions
- `.chezmoiignore` controls which files are skipped per platform
- `.chezmoiscripts/` contains install scripts that run on `chezmoi apply`
