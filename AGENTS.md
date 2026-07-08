# Agents

This is a [chezmoi](https://www.chezmoi.io/)-managed dotfiles repository. Source files here are templates that deploy to `$HOME`.

## Development Workflow Architecture

Parallel development runs through Claude Code's **agent view** (`claude agents`). Each dispatched
session auto-isolates into its own git worktree, so multiple tasks run concurrently without a
persistent slot setup. Worktrees land under `~/programming/worktrees/<name>/`; the main payaus repo
at `~/programming/payaus` keeps `master` checked out as a clean baseline (and is where shared-dev-DB
rails console and exploratory sessions run).

### PR Workflow

All PRs start as drafts. GitHub is the source of truth for PR status:
- **Draft** = work in progress, not yet self-reviewed or QA'd
- **Ready for review** = self-reviewed and manually QA'd, ready for peer review

### Finishing Work (PR approved and merged)

1. `gh pr merge <number> --squash --delete-branch`
2. `git town sync` (cleans up local branch)

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

**After editing any source file, always run bare `chezmoi apply` to deploy the changes to `$HOME`.** Don't target individual files (`chezmoi apply <path>`) — everything in this repo is meant to be applied, and a bare apply walks the whole tree, which correctly creates any brand-new directories (e.g. a new skill folder). A leaf-file target skips the directory entry and fails with `stat ... no such file or directory` on first deploy.

`chezmoi` here is a thin wrapper (`dot_local/bin/executable_chezmoi`, shadowing the real binary earlier on PATH). On `apply` it auto-reconciles *benign* JSON drift — a deployed JSON file an app reformatted without changing content gets `re-add`ed silently so it never blocks the apply. So a bare `chezmoi apply` no longer stops on pure reformatting.

**For any drift the wrapper does NOT auto-fix — semantic JSON changes (it prints `drifted semantically — left for review`) or non-JSON files — fix it immediately; never ignore it or route around it.** A message like `<file> has changed since chezmoi last wrote it` (often followed by a `could not open a new TTY` error in a non-interactive shell) means the *deployed* file was edited outside chezmoi, so the destination no longer matches source. Do NOT downgrade to a targeted `chezmoi apply <path>` to skip the drifted file — that leaves the tree permanently out of sync, which is the exact failure this rule exists to prevent. Instead:

1. `chezmoi diff <file>` to see what actually differs.
2. Reconcile it: if the on-disk change should be kept, fold it back into source with `chezmoi re-add <file>`; if source is authoritative, let `chezmoi apply` overwrite it.
3. Re-run bare `chezmoi apply` and confirm it completes clean.

The tree is only "done" when a bare `chezmoi apply` runs with no drift and no leftover targeted applies. Reconciling drift can mean choosing between the deployed edit and the source — if it's ambiguous which should win, surface the diff and ask rather than guessing.
