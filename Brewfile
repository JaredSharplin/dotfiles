# Brewfile - macOS package dependencies
# Install with: brew bundle

# Bootstrap
brew "chezmoi"        # dot_local/bin/executable_chezmoi wraps the real binary and aborts without it

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
# puma-dev, memcached, mailpit and MinIO come from payaus's Puppet run. Postgres does not — that
# manifest only checks for it.
brew "postgresql@17"  # keg-only; PATH in .zshenv so non-interactive shells get psql

# Hook dependencies
brew "jq"                      # inject-domain-map.sh parses its payload with it
brew "graphviz"                # `dot`, behind that hook's rake architecture_map:generate
brew "PeonPing/tap/peon-ping"  # settings.json wires 10 hook events to its peon.sh

# Casks
cask "ghostty"              # config in dot_config/ghostty/
cask "google-chrome"        # browser QA target; qa-handoff opens tabs in it
cask "karabiner-elements"   # config in dot_config/private_karabiner/
cask "rectangle"            # window management

# Deliberately absent: trash — macOS ships /usr/bin/trash.
