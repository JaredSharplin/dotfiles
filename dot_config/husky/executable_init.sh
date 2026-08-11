# Sourced by husky before every hook, in every repo that uses husky. Gives the
# personal cops a pre-commit gate without touching a project's tracked
# .husky/pre-commit. Advisory only — offences print, the commit still lands.
#
# Git runs hooks outside an interactive shell, so mise's shims have to be put
# back on PATH before ruby or rubocop will resolve.
PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

if [ "$(basename "$0")" = "pre-commit" ] && [ -x "$HOME/.local/bin/personal-rubocop" ]; then
  "$HOME/.local/bin/personal-rubocop" --staged || true
fi
