#!/bin/bash
# Install declared gh CLI extensions.
#
# chezmoi re-runs this whenever the list below changes (run_onchange_). It is
# named run_onchange_after_ so it runs *after* run_onchange_install-homebrew,
# which installs gh itself on a fresh machine.
#
# Installing an extension only downloads the public release binary — no auth
# needed here.

set -e

command -v gh >/dev/null 2>&1 || { echo "gh not installed — skipping extensions"; exit 0; }

extensions=(
  dlvhdr/gh-dash  # PR/issue dashboard TUI
  github/gh-stack # native stacked pull requests (link-github-stack calls it)
)

echo "Installing gh extensions..."
for ext in "${extensions[@]}"; do
  if gh extension list 2>/dev/null | grep -qF "$ext"; then
    echo "  ✓ $ext"
  else
    echo "  + installing $ext"
    gh extension install "$ext"
  fi
done
echo "gh extensions ready"
