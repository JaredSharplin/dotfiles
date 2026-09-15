# Brewfile - macOS package dependencies
# Install with: brew bundle

# Bootstrap
brew "chezmoi"        # This repo's own tool; dot_local/bin/executable_chezmoi wraps the real binary and aborts without it

# Essential tools
brew "gh"             # GitHub CLI (extensions declared in .chezmoiscripts/run_onchange_after_install-gh-extensions.sh)
brew "git-delta"      # Syntax-highlighting pager for git
brew "diffnav"        # GitHub-style file-tree diff pager (used by lazygit PR-diff commands)
brew "git-town"       # Git workflow automation
brew "neovim"         # Text editor
brew "lazygit"        # Git TUI
brew "zellij"         # Terminal multiplexer
brew "rustup"         # Rust toolchain manager (keg-only; PATH in .zshenv)

# Shell enhancements
brew "starship"             # Cross-shell prompt
brew "zoxide"               # Smarter cd command
brew "mise"                 # Development tool version manager (runtimes pinned in dot_config/mise/config.toml)
brew "mcfly"                # Command line fuzzy history search
brew "antidote"  # Fish-like autosuggestions for zsh

# Optional but recommended
brew "fzf"          # Fuzzy finder
brew "bat"          # Better cat with syntax highlighting
brew "glow"         # Markdown renderer for the terminal (PR bodies, etc.)
brew "timg"         # Terminal image/video viewer (PR screenshots via gh-pr-shots)
brew "eza"          # Modern ls replacement
brew "ripgrep"      # Better grep
brew "fd"           # Better find

# payaus native dev
# puma-dev, memcached, mailpit and MinIO come from payaus's own Puppet run
# (bin/native/ensure_running.sh) — not declared here. Postgres is NOT: that manifest only runs
# pg_isready and otherwise points at Postgres.app, so it has to already exist or the run exits 1.
brew "postgresql@17"  # keg-only; PATH in .zshenv, since non-interactive shells need psql for bin/rails db:*

# Hook dependencies
brew "jq"                      # dot_claude/hooks/inject-domain-map.sh parses its payload with it
brew "graphviz"                # `dot`, behind payaus's `rake architecture_map:generate` for that same hook
brew "PeonPing/tap/peon-ping"  # dot_claude/settings.json wires 10 hook events to its peon.sh

# Casks
cask "ghostty"              # Terminal; config in dot_config/ghostty/
cask "google-chrome"        # Browser QA target; qa-handoff opens tabs in it
cask "karabiner-elements"   # Config in dot_config/private_karabiner/
cask "rectangle"            # Window management

# Deliberately absent: trash — macOS ships /usr/bin/trash, and the Homebrew formula is keg-only.
