# Working together

These are the conventions I've settled on for this codebase. If a rule doesn't fit the situation, say so and explain — I'd rather revisit a rule than have you work around it silently. Push back if you see a better approach than what I've asked for.

Rules written as absolutes ("off the table", "not negotiable") genuinely have no exceptions. Everything else is a default you can reason about.

# Testing

Use `bin/rails test file.rb:123` — always include the line number. `bin/rails test` works regardless of native dev setup; the wrapper is only needed for other Rails commands.

Don't use `bin/dev test`.

## Writing tests

Good tests here look like:

- Deterministic — one execution path, no if/else branches
- Exact values — calculate expected results up front, assert against them directly
- `assert_in_delta expected, actual` with defaults, no extra arguments
- No comments or assertion messages
- Coverage is thorough — exercise the behavior, not just the happy path

Two absolutes:

- **Don't skip tests.** If the environment is blocking, fix the environment first.
- **Don't weaken an assertion to turn red green.** If a test fails, the cause is in the code or the test's logic. Matching the assertion to broken behavior defeats the point of the test.

```ruby
# Wrong
assert result > 0
if condition; assert_equal x, y; else; assert_nil z; end

# Right
hours = 5.0
rate = 25.10
expected = hours * rate  # 125.50
assert_in_delta expected, result
```

# Code Quality

## Linting commands

- `bundle exec rubocop` for Ruby linting
- `srb tc` for Sorbet type checking
- If either fails due to missing gems, run `bundle install` first

## Lints are not negotiable

When rubocop or Sorbet complains, restructure the code until it passes. Disable-comments (`# rubocop:disable`, `# T.unsafe`, `# typed: ignore`, weakening `# typed:` strictness, or any inline disable) are off the table — no exceptions.

A linter complaint is a real signal. Silencing it without fixing the cause hides the issue for later.

## User-facing strings

All user-facing strings must go through translation. Don't embed plain English directly.

## Use Enumerable, not C-style loops

Prefer Enumerable chains over initialize-plus-mutate loops.

```ruby
# Avoid                                    # Prefer
total = 0                                  total = items.sum(&:price)
items.each { |i| total += i.price }

names = []                                 names = users.filter_map { |u| u.name if u.active? }
users.each { |u| names << u.name if u.active? }

lookup = {}                                lookup = records.index_by(&:id)
records.each { |r| lookup[r.id] = r }
```

Chain methods fluently:

```ruby
users
  .select(&:active?)
  .reject(&:admin?)
  .map(&:email)
  .uniq
```

Use `.then` for transformations and `.tap` for side effects:

```ruby
# .then (also known as yield_self) - transform and return new value
User.find(id)
  .then { |user| UserPresenter.new(user) }
  .then { |presenter| presenter.as_json }

# .tap - do something with value, return original
User.new(params)
  .tap { |u| u.role = :member }
  .tap { |u| logger.info("Created: #{u.email}") }
  .save!
```

Key methods: `map`, `select`, `find`, `sum`, `group_by`, `index_by`, `filter_map`, `flat_map`, `then`, `tap`.

## Use Ruby 3.4 `it` in single-parameter blocks

Prefer `it` over named block parameters in short, single-parameter blocks. Use `&:method` for bare method calls, and named parameters for multi-arg blocks.

```ruby
# &:method for bare calls       # `it` when there's more to the expression
users.map(&:name)               users.map { it.name.downcase }
items.select(&:active?)         items.select { it.score > threshold }
                                prices.sum { it * tax_rate }
```

## Use Ruby 3 pattern matching

Prefer `case/in` over chains of `if`/`elsif` when destructuring hashes or arrays. Patterns match hash keys partially by default.

```ruby
# Hash destructuring
case response
in {status: 200, body:}  then process(body)
in {status: 404}         then not_found
in {status: 500, error:} then log_error(error)
end

# Array matching with find patterns
case items
in [*, {type: "error", message:}, *] then handle_error(message)
end

# Guard clauses
case user
in {role: "admin", active: true}            then grant_full_access
in {role:, score:} if score >= threshold    then grant_limited_access
end

# Single-pattern extraction with =>
config.dig(:database, :primary) => {host:, port:}
```

## Keyword arguments for multi-parameter methods

Use keyword args when a method takes more than one argument. Use shorthand syntax when the variable name matches the key.

```ruby
# Avoid
def create_user(name, email, role)
send_notification(user, "welcome", true)

# Prefer
def create_user(name:, email:, role:)
send_notification(user:, template: "welcome", immediate: true)

# Shorthand: `user:` is short for `user: user`
user = find_user(id)
send_notification(user:, template:)
```

# Scripting language

For dotfiles scripts, tooling, and automation (anything in `~/.config/task/scripts/`, `~/bin/`, or similar):

- **Use Ruby** — not bash, not Python, not TypeScript
- Bash is fine for scripts under ~15 lines that are purely command glue with no real logic
- Anything with JSON handling, conditional logic, string building, or multiple steps → Ruby

Shebang: `#!/usr/bin/env ruby`

Subprocess calls: Use backticks for simple captures, `IO.popen` or `Open3.capture3` for anything that needs stderr or exit status.

JSON: `require 'json'` — `JSON.parse(...)` and `.to_json`.

# Commands that cause real damage

Git operations (`git push`, `git push --force`, `git commit --amend`) are blocked by a Claude Code hook — see `dot_claude/hooks/executable_block-forbidden-git.sh`. Use `git town sync` / `git town propose` for pushing, and create new commits rather than amending.

For everything else, use the alternative — these aren't judgment calls:

| Don't use                                   | Use instead                                    | Why                                                             |
|---------------------------------------------|------------------------------------------------|-----------------------------------------------------------------|
| `bin/dev` for app dev (server, migrate, watch) | Native dev setup (`~/.config/payaus-native-dev/`) | Native dev is the default path for this developer; see below |
| `bin/rails runner`, `bin/rails console`, `bin/rails c`, `bin/rails db:*` | Native dev wrapper (`~/.config/payaus-native-dev/rails ...`) for local DB work; Grep/Read for code exploration; write a test for verification | **Hits the shared remote dev DB.** Hook-enforced — see `dot_claude/hooks/` |
| `sed -i`, `awk -i`, `perl -i`, `ruby -i`    | Read + Edit tools                              | Inline edits frequently introduce syntax errors, hard to reverse |
| `rm`                                        | `trash`                                        | Recoverable                                                      |
| `chezmoi apply --force`                     | `chezmoi apply` with review                    | Silently overwrites uncommitted edits                            |

## Bug investigation against the remote dev box

Most dev work for this developer is **local** (native dev or Docker, with isolated local DBs). The remote dev box is only used for **bug investigation** that requires the shared, prod-scrubbed dataset — typically reproducing a customer-reported issue.

The remote dev box is wired to the **main repo only** (`~/programming/payaus`). It does **not** work in worktrees. If a bug-investigation step needs `bin/dev`, switch to the main repo first.

For read-only investigation, the project ships a `/dev-console` skill in `payaus/.claude/skills/dev-console/`. That skill is the canonical contract:
- `bin/dev runner "..."` — preferred for one-shot reads (no interactive session)
- `bin/dev console --sandbox` — interactive REPL; `--sandbox` rolls back any accidental DB writes on exit
- Strict banned-methods list (no `save`, `update`, `create`, `destroy`, etc.) enumerated in the skill

These commands are allowed for read-only use. They are *not* in the same risk class as `bin/rails runner`/`console`, which connect to the shared DB without sandbox protection and are hook-enforced as forbidden.

# Native local development (puma-dev)

This developer has native local dev set up using puma-dev. It can be used in the main repo or any worktree. The project CLAUDE.md assumes a remote dev box — override that when native local dev is active.

## When to use native local dev

- Browser verification of changes via Chrome MCP
- Database operations on the local dev database
- Running the Rails app locally without Docker

## Setup a directory for native dev

```bash
~/.config/payaus-native-dev/setup-worktree.rb            # from inside a worktree, infers name from basename
~/.config/payaus-native-dev/setup-worktree.rb my-feature # explicit name
```

Deploys `.pumaenv` + initializer + puma-dev symlink, then runs `watch --once` to compile assets. After it finishes, the worktree is browser-ready at `https://<name>.test`.

The main repo uses `payaus` → `https://payaus.test`. Worktrees use their directory name (e.g. `my-feature` → `https://my-feature.test`).

## Ephemeral worktrees from agent view

When Claude Code's `EnterWorktree` tool runs (used by agent view, `Agent(isolation: "worktree")`, and `claude --worktree`), the new worktree lands at `~/programming/worktrees/<name>/` — same path as manually-created worktrees. Payaus's `WorktreeCreate` hook (`.claude/hooks/worktree-create.rb`) routes through `bin/manage-worktrees`, so dependencies and a per-worktree test database are installed automatically. `bin/rails test` works inside immediately.

Native dev is *not* set up by that hook — it's opt-in. When a task in an ephemeral worktree needs browser verification, run `setup-worktree.rb` (no args) from inside the worktree.

**Shared dev DB caveat:** all worktrees share `payaus_development` and `payaus_jobsdb_development`. Per-worktree isolation only applies to the *test* DB (via `TEST_ENV_NUMBER`). Two parallel browser-verifying sessions on branches with incompatible migrations will clash on the dev DB — uncommon but worth knowing.

## Rails commands in native local dev

**The core distinction:** bare `bin/rails` connects to the **shared remote developer database**. `~/.config/payaus-native-dev/rails` connects to your **local DB**. For DB-touching or Ruby-executing rails commands (`bin/rails db:*`, `bin/rails runner`, `bin/rails console`, `bin/rails rails_rbi:*`), use the wrapper. `bin/rails test` is the only safe bare invocation — the test suite doesn't hit the shared DB. (`bin/dev console` and `bin/dev runner` are a separate path — see *Bug investigation against the remote dev box* above.)

```bash
# Correct — local DB via wrapper
~/.config/payaus-native-dev/rails db:reset
~/.config/payaus-native-dev/rails db:migrate
~/.config/payaus-native-dev/rails runner '...'
~/.config/payaus-native-dev/rails console
~/.config/payaus-native-dev/rails rails_rbi:helpers   # regenerate sorbet/rails-rbi/*.rbi

# Wrong — shared remote dev DB
bin/rails db:reset      # would drop the shared developer database
bin/rails db:migrate    # migrates against shared DB
bin/rails runner '...'  # arbitrary code against shared DB
bin/rails console       # interactive session against shared DB
bin/rails rails_rbi:*   # boots Rails against shared DB to introspect helpers/models
```

**RBI regeneration is surgical, not bulk.** When Sorbet complains about a missing method on a new helper/model/route (e.g. `_()` not resolving on a new helper because `include Kernel` isn't injected yet), the fix is to update the relevant `sorbet/rails-rbi/*.rbi` file — *not* to add `include Kernel`, a `T.unsafe`, or any inline workaround.

For models, **always pass the model name(s)** as task args. Bare `rails_rbi:models` regenerates every model RBI and produces a huge noisy diff. The task accepts a comma-separated list:

```bash
~/.config/payaus-native-dev/rails 'rails_rbi:models[DataStream::Join]'
~/.config/payaus-native-dev/rails 'rails_rbi:models[Foo,Bar::Baz]'
```

(Quote the whole task arg — zsh interprets `[...]` as a glob.)

The other `rails_rbi:*` tasks don't take per-item args, but each only touches its own category of files (so the diff stays contained):

- `rails_rbi:helpers` → regenerates `sorbet/rails-rbi/helpers/*.rbi` only
- `rails_rbi:routes` → regenerates the routes RBI only
- `rails_rbi:mailers` → mailer RBIs only
- `rails_rbi:jobs` → job RBIs only
- `rails_rbi:active_record` → AR base RBI only

`rails_rbi:all` is off the table for fixing a single Sorbet error — it regenerates everything.

If a regen still touches an RBI file you didn't expect, revert that file: `git checkout -- sorbet/rails-rbi/<file>.rbi`. A noisy multi-file RBI churn in a PR diff is a bug, not normal — if you can't articulate why an RBI was touched, revert it.

**Migration file mutations are suppressed on native dev.** Upstream, `config/initializers/02_configuration/migration_timings.rb` prepends `MigrationTimings` to `ActiveRecord::Migration` and writes debug timing comments back into each migration `.rb` file on every `:up` run in development. That's signal on a prod-shaped dev box but pure noise on a tiny seeded local DB. The native-dev initializer (`~/.config/payaus-native-dev/initializer.rb`, deployed as `config/initializers/99_local_native_dev.rb` by `setup-worktree.rb`) no-ops `MigrationTimings#log_migration_timings` and `#clear_migration_timings` when `RUNNING_LOCAL_NATIVE_ENV=true`, so migrations run normally but never touch their own files. If you ever see migration-file diffs after `db:migrate`, the override isn't loaded — check that the worktree has `config/initializers/99_local_native_dev.rb` and `.pumaenv` exports `RUNNING_LOCAL_NATIVE_ENV=true`.

The wrapper sources `.pumaenv` which sets `BOOT_WITHOUT_SECRETS=true`. Without this, the vault loader overwrites local env vars with remote dev server credentials. Bare `bin/rails runner` / `console` / `c` / `db:*` are blocked by `dot_claude/hooks/executable_block-forbidden-git.sh` — the hook exists precisely because this failure mode is so destructive. The hook does **not** block `bin/dev console` / `bin/dev runner`, which are sandboxed/read-only and used for bug investigation against prod-shaped data via the project's `/dev-console` skill.

## Restarting the app

Use `~/.config/payaus-native-dev/restart my-feature`. This touches `tmp/restart.txt` (puma-dev's documented restart mechanism) then polls until the app finishes booting, since puma-dev returns 502 during the boot window. Without the wait, the next browser request may hit the 502 window and appear broken.

**Never pipe `restart` through `tail`/`head`.** On boot failure, the script already surfaces the Rails exception by parsing the dev-mode error page — the exception class and message print first, the middleware stack last. `tail -N` chops off the cause and leaves you staring at middleware noise. If output is too long, redirect to a file and read it with the Read tool. The `(no log file at … — can't surface diagnostics)` line is normal on first boot of an ephemeral worktree and not the error.

To stop all apps: `~/.config/payaus-native-dev/restart` with no argument — runs `puma-dev -stop`.

## Assets

`~/.config/payaus-native-dev/watch` compiles assets (writes to `public/assets/webpack/`, puma-dev serves them).

- Default: long-running `webpack --watch`. Use for iteration. **Never** launch in `run_in_background` with a piped `tail`/`head`/`grep` — pipe buffering hides the output. If you must stream it, grep `--line-buffered` for webpack's own `compiled .* in \d+ ms` marker.
- `watch --once`: compile once and exit. Use this before browser verification in a single-session flow (e.g. an agent about to run Chrome MCP).
- `watch --skip-install`: skip the `yarn install` check when you know the lockfile hasn't changed. (The wrapper already skips automatically when `yarn.lock` mtime hasn't moved since the last install — the flag is for short-circuiting that check itself.)

After recompiling assets, hard-refresh the browser (`ignoreCache: true` in Chrome MCP) to avoid stale cached bundles.

## Login credentials (local seeded DB)

Use the **Local Dev Cafe** org for browser verification, not Team Tanda (sysadmin).

- Login: `demoaccount+1@tanda.co` / `password123`

## Full documentation

See `~/.config/payaus-native-dev/README.md` for architecture, design decisions, and troubleshooting.

# Modifying config files

For any config file (gitignore, dotfiles, rc files):

1. **Investigate existing setup first.** Check what's already configured before making changes.
   - `git config --global core.excludesfile` to see the current gitignore
   - `ls -la ~/.*` for existing dotfiles
   - The solution may already exist
2. **Read, then Edit.** Use the Read tool first, then Edit for targeted changes. Don't use `echo >>` (appends blindly) or Write on an existing file (overwrites everything).
3. **Global gitignore:** check `git config --global core.excludesfile` first. User's global gitignore is at `~/.global_gitignore`.

# Git workflow

Use git town for branch management. Invoke the `/git-town` skill for detailed stacking guidance.

- `git town hack feature/name` to start branches
- `git town sync` instead of `git push`
- `git town propose` to open a PR (syncs and opens in one step)

## Commit and push cadence

- **Commit** when a logical unit of work is complete — not after every individual file edit
- **`git town sync`** only when explicitly asked
- A "commit and push" request in one message doesn't mean keep syncing after every subsequent change

## CI builds and pushing

Pushing is off by default (`push-branches = false` in global git config), which is what keeps CI spend down — no `[skip ci]` machinery needed. `git town sync` updates branches **locally only** and does not push, so intermediate syncs burn no Buildkite builds. The pushes that do happen are deliberate:

- `git town propose` pushes once when opening the PR — that's the build you want.
- `git town sync --push` pushes on purpose (e.g. to update an open PR with newly-synced changes).

The feature sync strategy is `merge` (not compress/rebase), so syncs never rewrite history — a later push is always a clean fast-forward. There is no `[skip ci]` hook.

## Git town behavior

When running `git town sync`, it will sometimes edit **unrelated PRs** to update the branch stack metadata shown in PR bodies (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`). This is normal — git town keeps stack navigation links correct across all PRs in the stack. Not an error.

## When a test fails on your branch

Tests pass on master — CI enforces this. If a test is red on your branch, your diff caused it.

- Use `git diff master -- <file>` to see what you changed
- Don't check out master or stash to "verify" — it's a dead end and leaves the repo in a messy state
- Re-run the test once before debugging; fixtures can be transient. If it fails a second time, it's your code.
- There's no such thing as a "pre-existing failure" on your branch — fix forward

# GitHub PRs

## Analyzing PR changes

**For PR review, `git diff master` is off the table in every form** — including `git diff master -- <path>`, `git diff origin/master`, and any equivalent. Use `gh pr diff <number>`.

Why: local master is often stale, which silently injects unrelated changes into the diff and leads to wrong conclusions. `git diff` also includes merge commit artifacts that distort the file list. Only `gh pr diff` shows the true PR diff that reviewers see.

Workflow:
1. Check PR size: `gh pr view <number> --json additions,deletions`
2. Small (<1000 lines): `gh pr diff <number>` with no flags
3. Large: `gh pr diff <number> --name-only` first, then read specific files

Don't use `--patch` — it shows individual commit patches, not the net PR diff.

## Creating PRs

```bash
git town propose --title "..." --body "..."
gh pr edit --add-assignee @me --add-label <type-label> --add-label built-in-australia
```

`git town propose` syncs the branch, pushes it, and opens the PR in one step — no separate `git town sync` needed before propose, and its push is what triggers CI on the PR.

Every PR must have (set via `gh pr edit` after create):

- `--add-assignee @me` — always assign yourself
- `--add-label built-in-australia` — always added to every PR
- `--add-label <type-label>` — pick one: `feature`, `bug`, `api-only`, `not-user-facing`, `security`, `refactor`

Choose the type label based on the nature of the change. If unsure, ask before creating the PR.

## Editing PR bodies

Don't replace a PR body wholesale — the user may have made manual edits (checked boxes, added notes) that would be lost.

Before editing:

1. Fetch the current body: `gh pr view <number> --json body -q '.body'`
2. Make incremental changes — modify only the specific section you need to change
3. If adding a new section, append rather than rewriting everything

# Shape docs

Shape Up planning lives at `~/notes/shaping/<project>/`. Standard files:

- `frame.md` — the pitch: source quote, problem, appetite, no-gos
- `shaping.md` — current state, outcome-framed requirements (R0..Rn), rabbit holes, fat-marker sketch
- `slices.md` — vertical slices (V1..Vn), each ending in a concrete demo
- `spike-*.md` — focused technical investigations referenced from the above
- `V<n>-pr-stack.md` — per-slice PR stack mapping (added when a slice goes into flight)

When picking up work on a slice, read at least `frame.md`, `slices.md`, and the relevant `V<n>-pr-stack.md` before planning. `shaping.md` is the deep reference — read it when a requirement's intent is unclear. Spikes are background — read the ones a slice or stack explicitly cites.

Frontmatter `shaping: true` marks these files so tooling can find them.

# Working style

- When I reference a documentation file, read the entire file in one pass — don't chunk for token savings. Thoroughness beats token efficiency for technical docs.
- When you think I'm wrong or asking for the wrong thing, say so before acting on it.
- If a rule here doesn't fit the current context, flag it — these are guidelines for the common case, not traps.
- **Use the AskUserQuestion tool to ask questions.** Don't present options as prose menus.
