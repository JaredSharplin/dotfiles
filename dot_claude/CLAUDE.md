# Working together

Conventions I've settled on. If a rule doesn't fit the situation, say so — I'd rather revisit a rule than have you work around it silently. Push back if you see a better approach.

Absolutes ("off the table", "not negotiable") have no exceptions. Everything else is a default you can reason about.

# Design rhythm

Two principles from Kent Beck — how we keep design quality from drifting as features land.

## Beck's four rules of simple design

Priority order — when two tension, the higher wins:

1. **Passes the tests** — correctness is non-negotiable.
2. **Reveals intention** — code communicates its purpose.
3. **No duplication** — state every fact once.
4. **Fewest elements** — remove anything not serving 1-3. No speculative abstractions.

Rules 2 and 3 can pull apart — making something DRY can obscure intent. Resolve by refactoring, not by abandoning either. If you can't reconcile them, raise it.

Two duplication blind spots the agent loop misses while writing — they're global properties, invisible mid-generation, so catch them on the exhale:

- **Derived state stored as a field** — an ivar/attribute/flag that's a pure function of state already held. Make it a method.
- **Reinvented mechanism** — hand-rolled code duplicating what the framework or codebase already provides. Reuse it.

Naming (rule 2) applies continuously, not just on the exhale: optimise for correctness and clarity, never brevity. Use the domain's own word (schema and associations are the dictionary), spelled out however verbose. Never a name that's *false* about what the code does — `will_create` on a class that only fills existing records is a lie; so is `token` for a value that isn't one.

## Inhale / exhale

The agent-loop default is to add features without stepping back, which degrades design fast. Counter it with two phases, commits in between:

- **Inhale (RED → GREEN):** failing test, simplest implementation that passes, *commit*.
- **Exhale (REFACTOR):** with the test green, review for duplication (derived state, reinvented mechanism), leaky abstractions, drifted names, dead branches. Apply Beck's four rules. *Commit the cleanup separately* — never mix feature and refactor.

The exhale isn't optional; skipping it compounds complexity. Only exemption: genuinely-trivial changes (typos, single-line config).

For payaus, the canonical exhale tool is `/simplify-with-analysis` — gathers findings report-only (a `/code-review` pass, a cold Beck-rules subagent, and `bin/diff-quality`: rubycritic + SimpleCov coverage vs `master`), posts one consolidated summary before editing, then applies one follow-up pass. Other projects: `/simplify` (built-in) is fine.

# Testing

Use `bin/rails test file.rb:123` — always with the line number. Don't use `bin/dev test`.

## Writing tests

Good tests here:

- Deterministic — one execution path, no if/else
- Exact values — calculate expected up front, assert directly
- `assert_in_delta expected, actual` with defaults, no extra arguments — **except payroll tests** (below)
- No comments or assertion messages
- Thorough coverage — exercise the behavior, not just the happy path

**Payroll tests are exact.** In `test/**/payroll*/**/*`, never `assert_in_delta` — use exact `assert_equal`. Payroll values must be exact; a rounding gap means the production code or the assertion is wrong, not that a delta is acceptable. Enforced by the `TandaCustomCops/NoAssertInDelta` cop.

Two absolutes:

- **Don't skip tests.** If the environment is blocking, fix the environment first.
- **Don't weaken an assertion to turn red green.** A failure means the code or the test's logic is wrong. Matching the assertion to broken behavior defeats the point.

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

- `bundle exec rubocop` — Ruby
- `srb tc` — Sorbet
- If either fails on missing gems, `bundle install` first.

## Lints are not negotiable

When rubocop or Sorbet complains, restructure the code until it passes. Disable-comments (`# rubocop:disable`, `# T.unsafe`, `# typed: ignore`, weakening `# typed:` strictness, or any inline disable) are off the table — no exceptions. A complaint is a real signal; silencing it without fixing the cause hides the issue.

## Sorbet sigil for new Ruby files

New app-code Ruby files must start `# typed: strict` — not `false`, not `ignore`. Non-negotiable for app code, except controllers (`# typed: true`). (Tests, scripts, and other non-app files are exempt.)

Under `strict`: every method needs a `sig`, every constant and instance variable a declared type, no implicit `T.untyped` escapes. Write the `sig`s as you write the methods. If `srb tc` complains, fix the types — don't downgrade the sigil.

## User-facing strings

All go through translation. Don't embed plain English directly.

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

Use keyword args when a method takes more than one argument. (Shorthand syntax — `user:` for `user: user` — is enforced by RuboCop `Style/HashSyntax`, so it's not repeated here.)

```ruby
# Avoid
def create_user(name, email, role)
send_notification(user, "welcome", true)

# Prefer
def create_user(name:, email:, role:)
send_notification(user:, template: "welcome", immediate: true)
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
| `bin/dev` for app dev (server, migrate, watch) | Native dev (`bin/native/ensure_running.sh`, then bare `bin/rails`) | Native dev is the default path for this developer; see below |
| `sed -i`, `awk -i`, `perl -i`, `ruby -i`    | Read + Edit tools                              | Inline edits frequently introduce syntax errors, hard to reverse |
| `rm`                                        | `trash`                                        | Recoverable                                                      |
| `chezmoi apply --force`                     | `chezmoi apply` with review                    | Silently overwrites uncommitted edits                            |

## Bug investigation against the remote dev box

Most dev work here is **local** (native dev or Docker, isolated local DBs). The remote dev box is only for **bug investigation** needing the shared, prod-scrubbed dataset — typically reproducing a customer issue.

The read-only `bin/dev console`/`runner` path (below) runs from the **main repo** (`~/programming/payaus`) — switch there first if a bug-investigation step needs it. Full remote-devbox *QA* does work per-worktree, though: `qa-up` / the `/qa` skill infers the worktree from cwd and brings up a tunneled `qa-<worktree>` session against the shared dataset. That's a separate path from the read-only console here.

For read-only investigation, the project ships a `/dev-console` skill in `payaus/.claude/skills/dev-console/`. That skill is the canonical contract:
- `bin/dev runner "..."` — preferred for one-shot reads (no interactive session)
- `bin/dev console --sandbox` — interactive REPL; `--sandbox` rolls back any accidental DB writes on exit
- Strict banned-methods list (no `save`, `update`, `create`, `destroy`, etc.) enumerated in the skill

These `bin/dev` commands target the remote shared DB and are allowed for read-only use only. (Bare `bin/rails` is the *local* native-dev path — see below — not a remote-DB command.)

# Native local development (puma-dev)

This developer runs the app natively via payaus's shipped native dev setup (puma-dev; PR #45524 + follow-ups), in the main repo or any worktree. The project CLAUDE.md assumes a remote dev box — override that when native dev is active.

Local DB targeting is automatic. `RUNNING_LOCAL_NATIVE_ENV=true` is exported from `~/.zshenv` — not `~/.zshrc`, because `.zshenv` is read by *every* shell, including the non-interactive ones agents and hooks run in. So `config/boot.rb` loads the repo's `.env.local` (localhost DB + `IN_CONTAINER`) and bare `bin/rails` hits the **local** DB — no wrapper. `config/boot.rb` skips `.env.local` in the test env, so tests stay clean.

## When to use native local dev

- Browser verification of changes via Chrome MCP
- Database operations on the local dev database
- Running the Rails app locally without Docker

## Setup a directory for native dev

```bash
bin/native/ensure_running.sh   # from inside the repo or worktree
```

Installs/starts services (puma-dev, Postgres, MinIO, memcached, mailpit), writes a domain-templated `.env.local` (`APP_HOST_URL=<dirname>.test`), and creates the puma-dev symlink. After it finishes, the directory is browser-ready at `https://<dirname>.test`. It leaves a dotfiles-managed `~/.zshenv` untouched (it detects the existing `RUNNING_LOCAL_NATIVE_ENV`).

The main repo → `https://payaus.test`. Worktrees use their directory name (e.g. `my-feature` → `https://my-feature.test`).

## Ephemeral worktrees from agent view

When Claude Code's `EnterWorktree` tool runs (used by agent view, `Agent(isolation: "worktree")`, and `claude --worktree`), the new worktree lands at `~/programming/worktrees/<name>/` — same path as manually-created worktrees. Payaus's `WorktreeCreate` hook (`.claude/hooks/worktree-create.rb`) routes through `bin/manage-worktrees`, so dependencies and a per-worktree test database are installed automatically. `bin/rails test` works inside immediately.

Native dev is *not* set up by that hook — it's opt-in. When a task in an ephemeral worktree needs browser verification, run `bin/native/ensure_running.sh` from inside the worktree.

**Shared dev DB caveat:** all worktrees share `payaus_development` and `payaus_jobsdb_development`. Per-worktree isolation only applies to the *test* DB (via `TEST_ENV_NUMBER`). Two parallel browser-verifying sessions on branches with incompatible migrations will clash on the dev DB — uncommon but worth knowing. This is awareness only — **never** a reason to hesitate on, ask about, or propose isolating the DB for a pending migration (see *Pending migrations are not a decision point* below).

## Rails commands in native local dev

Bare `bin/rails ...` runs against the **local** DB (via the marker + `.env.local` mechanism described above). Just run it — migrations and other local DB work are expected and safe, don't ask first. `bin/rails test` uses the test DB.

If `.env.local` is missing, dev `bin/rails` won't reach the shared remote DB in practice: the vault can't decrypt secrets locally and the remote DB host isn't reachable from your machine, so it errors rather than connecting. Run `bin/native/ensure_running.sh` to (re)create `.env.local`.

(`bin/dev console`/`runner` are the separate remote-box path — see *Bug investigation against the remote dev box* above.)

**Pending migrations are not a decision point.** A `PendingMigrationError`, or pending migrations blocking boot/QA, means: run `bin/rails db:migrate` — however many are pending, don't ask, don't propose isolating the worktree's DB, don't skip QA over it. The shared-DB caveat above is awareness, not a veto. (`db:reset`/`db:drop` discard data — those are the only local DB commands worth confirming first.)

```bash
bin/rails db:reset
bin/rails db:migrate
bin/rails runner '...'
bin/rails console
bin/rails rails_rbi:helpers   # regenerate sorbet/rails-rbi/*.rbi
```

**RBI regeneration is surgical, not bulk.** When Sorbet complains about a missing method on a new helper/model/route (e.g. `_()` not resolving on a new helper because `include Kernel` isn't injected yet), the fix is to update the relevant `sorbet/rails-rbi/*.rbi` file — *not* to add `include Kernel`, a `T.unsafe`, or any inline workaround.

For models, **always pass the model name(s)** as task args. Bare `rails_rbi:models` regenerates every model RBI and produces a huge noisy diff. The task accepts a comma-separated list:

```bash
bin/rails 'rails_rbi:models[DataStream::Join]'
bin/rails 'rails_rbi:models[Foo,Bar::Baz]'
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

**Migrations don't rewrite their own timing comments on native dev.** Payaus no-ops `MigrationTimings` file mutations when `RUNNING_LOCAL_NATIVE_ENV=true` (shipped in the native setup), so `db:migrate`/`db:reset` run normally but never touch the migration `.rb` files. If you ever see migration-file diffs after `db:migrate`, the marker isn't set in that shell.

## Restarting the app

Use `bin/native/restart`. It touches `tmp/restart.txt` (puma-dev's restart mechanism) then polls until the app finishes booting (puma-dev returns 502 during the boot window) and recovers a wedged app. Without the wait, the next browser request may hit the 502 window and appear broken.

**Never pipe `bin/native/restart` through `tail`/`head`.** On boot failure it surfaces the Rails exception by parsing the dev-mode error page — the exception class and message print first, the middleware stack last. `tail -N` chops off the cause and leaves you staring at middleware noise. If output is too long, redirect to a file and read it with the Read tool.

## Assets

`yarn watch` compiles assets with `webpack --watch` (writes to `public/assets/webpack/`, puma-dev serves them). No port, so multiple worktrees can build in parallel — unlike `yarn serve` (webpack-dev-server, port 8081, one per machine, HMR).

- **Never** launch `yarn watch` in `run_in_background` with a piped `tail`/`head`/`grep` — pipe buffering hides the output. If you must stream it, grep `--line-buffered` for webpack's own `compiled .* in \d+ ms` marker.
- For a one-shot compile before browser verification (e.g. an agent about to run Chrome MCP), use `yarn build` (compiles once and exits).

After recompiling assets, hard-refresh the browser (`ignoreCache: true` in Chrome MCP) to avoid stale cached bundles.

## Login credentials (local seeded DB)

Use the **Local Dev Cafe** org for browser verification, not Team Tanda (sysadmin).

- Login: `demoaccount+1@tanda.co` / `password123`

## Full documentation

See `docs/local-native-setup.md` in payaus for setup, architecture, and troubleshooting.

# Modifying config files

For any config file (gitignore, dotfiles, rc files):

1. **Investigate first.** Check what's already configured — the solution may already exist. `git config --global core.excludesfile` for the current gitignore, `ls -la ~/.*` for existing dotfiles.
2. **Read, then Edit.** Never `echo >>` (appends blindly) or Write on an existing file (overwrites everything).
3. **Global gitignore** lives at `~/.global_gitignore`.

# Git workflow

Use git town for branch management. Invoke the `/git-town` skill for detailed stacking guidance.

- `git town hack feature/name` to start branches
- `git town sync` instead of `git push`
- `git town propose` to open a PR (syncs and opens in one step)

## Commit and push cadence

- **Commit** when a logical unit of work is complete — not after every file edit
- **`git town sync`** only when explicitly asked; a one-time "commit and push" doesn't mean keep syncing after every later change

## Commit messages

Write very short commit messages.

## CI builds and pushing

Pushing is off by default (`push-branches = false`), which keeps CI spend down — no `[skip ci]` machinery needed. `git town sync` updates branches **locally only**, so intermediate syncs burn no Buildkite builds. The deliberate pushes:

- `gh pr create --draft` pushes the branch and opens the PR (see *Creating and editing PRs*). Because it opens as a draft, no CI runs yet.
- `git town sync --push` pushes on purpose (e.g. to update an open PR).

**Draft PRs run no CI.** Buildkite skips the pipeline on a draft PR unless it carries the `run-bk` label (payaus #56255; the skip fails open, so an API hiccup runs CI rather than skipping it). A PR's first CI run happens when you mark it **ready for review** — lining CI up with the QA gate. To run CI on a still-draft PR, add the `run-bk` label.

Feature sync strategy is `merge` (not compress/rebase), so syncs never rewrite history — a later push is always a clean fast-forward.

## Git town behavior

When running `git town sync`, it will sometimes edit **unrelated PRs** to update the branch stack metadata shown in PR bodies (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`). This is normal — git town keeps stack navigation links correct across all PRs in the stack. Not an error.

## When a test fails on your branch

Master is always green — CI enforces it on every merge. So a red test on your branch was caused by your diff; "master must be broken" is never the explanation.

**The gate (no exceptions):** any red run → re-run it once → *only then* reason about the cause. You may not state or act on any conclusion — "flaky", "not my diff", "pre-existing", "environmental", "too big to be mine" — until the re-run completes. A failure count larger or weirder than your diff (22 failures from a 4-test change) is the *strongest* reason to re-run, never grounds to skip it — it means you don't understand the situation yet, not that the cause is environmental.

**Checking out or stashing to master "to verify" is off the table — no exceptions.** The premise (that master might be the problem) is known false, so there's nothing to verify there.

After the re-run, if it's still red it's your code: `git diff master -- <file>` to see what you changed, and fix forward. There's no "pre-existing failure" on your branch.

# GitHub PRs

## Analyzing PR changes

**When reviewing a PR, don't inspect its diff with `git diff master` in any form** — not `git diff master -- <path>`, not `git diff origin/master`, nor any equivalent. Use `gh pr diff <number>`. Local master is often stale (injects unrelated changes) and `git diff` includes merge-commit artifacts that distort the file list; only `gh pr diff` shows the true PR diff reviewers see. (This is about inspecting a *PR's* diff — using `git diff master -- <file>` to see your own branch's changes while fixing a failing test, as in *When a test fails on your branch* above, is a different thing and fine.)

Workflow:
1. Check size: `gh pr view <number> --json additions,deletions`
2. Small (<1000 lines): `gh pr diff <number>`, no flags
3. Large: `gh pr diff <number> --name-only` first, then read specific files

Don't use `--patch` — it shows individual commit patches, not the net diff.

## Creating and editing PRs

Invoke the `/git-town` skill before any PR work — it holds the mechanics: the `git town sync` → `gh pr create --draft` sequence, the required assignee/labels (`built-in-australia` + one type label), the screenshot capture/upload workflow, and the surgical PR-body edit rules (never wholesale-replace a body).

Two things always hold, skill loaded or not:

- **Every PR starts as a draft** — *not yet marked ready by me; the ready-flip is my review gate.* Marking it ready (`gh pr ready`) kicks off its first CI run; do that only when I ask.
- **Browser QA and screenshots are yours — automatic, not a handoff.** For anything user-visible, run the browser QA on native dev and fill the PR's Screenshots section *before* handing back — never leave placeholders or defer it to me. Skip only for a change with no user-visible surface, and say so explicitly.

# Shape docs

Shape Up planning lives at `~/notes/shaping/<project>/`. Invoke the `shaping` skill before shaping work or picking up a slice — it holds the file layout (`frame`/`shaping`/`slices`/`spike-*`/`pr-stack`), the pickup read-order, the `shaping: true` frontmatter rule, and the full methodology.

# Working style

- When I reference a documentation file, read all of it in one pass — don't chunk it or skip sections to save tokens. (This is about *reading* input, not about output length.)
- **Stay within the approved scope on destructive or multi-step tasks.** Do exactly what I approved; treat anything beyond it as a fresh decision to surface — even an item that looks "obviously in the same category." When the ground differs from the plan (unexpected file, branch, a worktree with a live session), stop and report. Recovery and undo actions (restore, re-create, kill a process, move uncommitted work) each need their own go-ahead. Read-only investigation needs none of this — the bar is only on state changes.
- **Do the hard work, not the shortcut.** On reviews, read the PR body, trace the call stacks, and evaluate test coverage. Back claims with evidence from the code. Take the correct path even when it costs more than the easy one. (This is about effort and rigor, not word count — a terse answer can be fully rigorous.)
- **When I ask a question, the answer is the deliverable — give it its own turn, ending with no tool call.** Prose in a turn that then fires tools scrolls out of view behind the tool output and never reaches me. Write the answer, stop, end the turn; resume tool work next turn. This is for genuine questions ("why did X?", "which approach is better?") where my reply is what you asked for — not a license to fragment ordinary task execution, where doing the work and reporting in one turn is right. Litmus: if I'd want to read your reasoning and maybe redirect before you act, isolate it.
- **Use the AskUserQuestion tool to ask questions** — not prose menus — and make the modal self-contained. The question text and each option's description are all I see, so put the whole decision there: what's being decided, what each option concretely does, and the tradeoff. Someone who hasn't read the conversation should be able to answer from the modal alone.
- **Declining to act on feedback is my call.** Applying a clearly-genuine fix is fine, but a decision *not* to act on a finding — skip, keep-as-is, dispute — comes to me, never a silent mid-stream note.
