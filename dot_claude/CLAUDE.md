# Working together

These are the conventions I've settled on for this codebase. If a rule doesn't fit the situation, say so and explain — I'd rather revisit a rule than have you work around it silently. Push back if you see a better approach than what I've asked for.

Rules written as absolutes ("off the table", "not negotiable") genuinely have no exceptions. Everything else is a default you can reason about.

# Design rhythm

Two principles, both adapted from Kent Beck. Together they're how we keep design quality from drifting as features land.

## Beck's four rules of simple design

In priority order — when two rules tension, the higher-priority one wins:

1. **Passes the tests** — correctness is non-negotiable.
2. **Reveals intention** — code communicates its purpose to readers.
3. **No duplication** — state every fact once and only once.
4. **Fewest elements** — remove anything that doesn't serve rules 1-3. No speculative abstractions.

Rules 2 and 3 sometimes pull in opposite directions — making something DRY can obscure intent. Resolve by *refactoring*, not by abandoning either rule. If you can't reconcile them, raise it rather than silently picking.

## Inhale / exhale

The agent-loop default is to add features without ever stepping back. That degrades design quickly. Counter it with a two-phase rhythm, with commits in between:

- **Inhale (RED → GREEN):** write a failing test, make it pass with the simplest implementation that works, *commit*.
- **Exhale (REFACTOR):** with the test green, review the change for duplication, leaky abstractions, names that drifted, and dead branches. Apply Beck's four rules. *Commit the cleanup separately* — never mix feature work and refactor in one commit.

The exhale is not optional. Skipping it is how complexity compounds. The only exemptions are genuinely-trivial changes (typo fixes, single-line config tweaks).

For payaus, the canonical exhale tool is the `/simplify-with-analysis` skill — runs `/simplify`, then `bin/diff-quality` (rubycritic + SimpleCov coverage vs `master`), with a one-follow-up-pass discipline. For other projects, just `/simplify` (built-in) is fine.

# Testing

Use `bin/rails test file.rb:123` — always include the line number.

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

## Sorbet sigil for new Ruby files

New Ruby files in app code must start with `# typed: strict`. Not `false`, not `ignore` — `strict`. This is non-negotiable for app code, except controllers, which use `# typed: true`. (Tests, scripts, and other non-app files are not covered by this rule.)

Under `strict`, every method needs a `sig`, every constant and instance variable needs a declared type, and there are no implicit `T.untyped` escapes. Write the `sig`s as you write the methods — don't defer them. If `srb tc` complains, fix the types; don't downgrade the sigil.

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
| `bin/dev` for app dev (server, migrate, watch) | Native dev (`bin/native/ensure_running.sh`, then bare `bin/rails`) | Native dev is the default path for this developer; see below |
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

These `bin/dev` commands target the remote shared DB and are allowed for read-only use only. (Bare `bin/rails` is the *local* native-dev path — see below — not a remote-DB command.)

# Native local development (puma-dev)

This developer runs the app natively via payaus's shipped native dev setup (puma-dev; PR #45524 + follow-ups), in the main repo or any worktree. The project CLAUDE.md assumes a remote dev box — override that when native dev is active.

Local DB targeting is automatic: `RUNNING_LOCAL_NATIVE_ENV=true` is exported from `~/.zshrc`, so `config/boot.rb` loads the worktree's `.env.local` (localhost DB + `IN_CONTAINER`) and bare `bin/rails` runs against the **local** DB. No wrapper.

## When to use native local dev

- Browser verification of changes via Chrome MCP
- Database operations on the local dev database
- Running the Rails app locally without Docker

## Setup a directory for native dev

```bash
bin/native/ensure_running.sh   # from inside the repo or worktree
```

Installs/starts services (puma-dev, Postgres, MinIO, memcached, mailpit), writes a domain-templated `.env.local` (`APP_HOST_URL=<dirname>.test`), and creates the puma-dev symlink. After it finishes, the directory is browser-ready at `https://<dirname>.test`. It leaves a dotfiles-managed `~/.zshrc` untouched (it detects the existing `RUNNING_LOCAL_NATIVE_ENV`).

The main repo → `https://payaus.test`. Worktrees use their directory name (e.g. `my-feature` → `https://my-feature.test`).

## Ephemeral worktrees from agent view

When Claude Code's `EnterWorktree` tool runs (used by agent view, `Agent(isolation: "worktree")`, and `claude --worktree`), the new worktree lands at `~/programming/worktrees/<name>/` — same path as manually-created worktrees. Payaus's `WorktreeCreate` hook (`.claude/hooks/worktree-create.rb`) routes through `bin/manage-worktrees`, so dependencies and a per-worktree test database are installed automatically. `bin/rails test` works inside immediately.

Native dev is *not* set up by that hook — it's opt-in. When a task in an ephemeral worktree needs browser verification, run `bin/native/ensure_running.sh` from inside the worktree.

**Shared dev DB caveat:** all worktrees share `payaus_development` and `payaus_jobsdb_development`. Per-worktree isolation only applies to the *test* DB (via `TEST_ENV_NUMBER`). Two parallel browser-verifying sessions on branches with incompatible migrations will clash on the dev DB — uncommon but worth knowing. This is awareness only — **never** a reason to hesitate on, ask about, or propose isolating the DB for a pending migration (see *Pending migrations are not a decision point* below).

## Rails commands in native local dev

Bare `bin/rails ...` runs against the **local** DB — the `~/.zshrc` marker plus the worktree's `.env.local` make it local. Just run it; migrations and other local DB work are expected and safe, don't ask first. `bin/rails test` uses the test DB. If the marker or `.env.local` is missing, `bin/rails` **fails closed** (crashes at boot on missing env / undecryptable vault secrets) rather than reaching a remote DB — it does not silently hit the shared dev DB. (`bin/dev console`/`runner` are the separate remote-box path — see *Bug investigation against the remote dev box* above.)

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

## Commit messages

Write very short commit messages.

## CI builds and pushing

Pushing is off by default (`push-branches = false` in global git config), which is what keeps CI spend down — no `[skip ci]` machinery needed. `git town sync` updates branches **locally only** and does not push, so intermediate syncs burn no Buildkite builds. The pushes that do happen are deliberate:

- `git town propose` pushes once when opening the PR — that's the build you want.
- `git town sync --push` pushes on purpose (e.g. to update an open PR with newly-synced changes).

The feature sync strategy is `merge` (not compress/rebase), so syncs never rewrite history — a later push is always a clean fast-forward. There is no `[skip ci]` hook.

## Git town behavior

When running `git town sync`, it will sometimes edit **unrelated PRs** to update the branch stack metadata shown in PR bodies (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`). This is normal — git town keeps stack navigation links correct across all PRs in the stack. Not an error.

## When a test fails on your branch

Master is always green — CI enforces it on every merge. So a red test on your branch was caused by your diff. "Master must be broken" is never the explanation.

**The gate (no exceptions):** any red run → re-run it once → *only then* reason about the cause. You may not state or act on any conclusion about why it failed — "flaky", "not my diff", "pre-existing", "environmental", "too big to be mine" — until the re-run has completed.

A failure count larger or weirder than your diff is the *strongest* reason to re-run, never grounds to skip it. A surprising shape (22 failures from a 4-test change) means you don't yet understand the situation — it is never evidence the cause is environmental or on master.

**Checking out or stashing to master "to verify" is off the table — no exceptions.** The premise (that master might be the problem) is already known to be false, so there is nothing to verify there.

After the re-run, if it's still red it's your code: use `git diff master -- <file>` to see what you changed, and fix forward. There's no such thing as a "pre-existing failure" on your branch.

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
- `pr-stack.md` — PR stack mapping (added when work goes into flight)

When picking up work on a slice, read at least `frame.md`, `slices.md`, and `pr-stack.md` before planning. `shaping.md` is the deep reference — read it when a requirement's intent is unclear. Spikes are background — read the ones a slice or stack explicitly cites.

Frontmatter `shaping: true` marks these files so tooling can find them.

# Working style

- When I reference a documentation file, read the entire file in one pass — don't chunk for token savings. Thoroughness beats token efficiency for technical docs.
- When you think I'm wrong or asking for the wrong thing, say so before acting on it.
- If a rule here doesn't fit the current context, flag it — these are guidelines for the common case, not traps.
- **Stay within the approved scope on destructive or multi-step tasks.** Do exactly what I approved, and treat anything beyond it as a fresh decision to surface. When the ground differs from the plan — an unexpected file or branch, a worktree with a live session — stop and report what you found so I can decide. Surface a discovered item even when it looks "obviously in the same category" as an approved one. Recovery and undo actions (restore, re-create, kill a process, move uncommitted work) each need their own go-ahead. Read-only investigation needs none of this — the bar is only on actions that change state.
- **Do the hard work, not the shortcut.** On reviews, read the PR body, trace the call stacks, and evaluate test coverage. Back claims with evidence from the code. Take the correct path even when it costs more than the easy one.
- **When I ask a question, the answer is the deliverable — give it its own turn and end with no tool call.** Don't bundle an answer with the tool calls it prompts. Prose emitted in a turn that then fires tools gets buried in the activity stream — it scrolls out of view behind the tool output, so for practical purposes the answer never reaches me (and on AskUserQuestion turns the harness hides it outright — see below). Write the answer, stop, end the turn; pick the tool work back up in the *next* turn, once I've read it and responded. This is about genuine questions — "why did X happen?", "which approach is better?", "what's the cause?" — where my reply is the thing you asked for. It is *not* a license to fragment ordinary task execution, where doing the work and reporting the result in the same turn is exactly right. The litmus test: if I'd want to read your reasoning and possibly redirect before you act on it, isolate the answer. The AskUserQuestion convention below is the strict instance of this same rule.
- **Use the AskUserQuestion tool to ask questions.** Don't present options as prose menus. But the tool is not a substitute for thinking:
  - **Framing must be its own turn. Never put it in the same turn as the tool call.** Mechanically: the harness hides any prose I emit in the turn that calls AskUserQuestion — I see *only* the forced-choice modal (the question text and the option labels), never the surrounding text. So framing bundled with the call does not reach me at all, however good it is. "Frame in the text before the tool call" is therefore the wrong instruction — the only framing I can actually read is framing delivered in a turn that **ends with no tool call**. So: write the framing, stop, end the turn. Then, in a *later* turn — after I've read it and responded — call AskUserQuestion. This is unconditional, not only when I ask to be "walked through first." If a question needs any context beyond what fits in the question text and the option labels themselves, that context must go in a prior turn or I will never see it. The bonus: a separate framing turn is also where I get to push on the premise or redirect before being forced to pick — the modal has no "wait, back up" (that's just "Other," a workaround).
  - What the framing turn must contain. Say what's being decided, what each option concretely does, and what the tradeoff is — *per question* if you're batching several (e.g. code-review findings), never one shared preamble for five decisions. A project-state recap is *not* framing: it summarizes where we are, not what this specific question controls or how the options differ. The bar is self-containment: someone who hasn't read the conversation could answer from that turn alone. If they'd need to scroll up or ask me anything, it isn't done — keep writing. Me having to ask "why?" or "more context?" is the failure this prevents; assume I won't ask, so if the framing doesn't stand on its own, I'm simply stuck.
  - When I ask for context on a pending question ("give me more context", "why are you asking this", "explain that"), treat it as a standalone writing deliverable, not a prompt to re-ask. The correct response is to *explain the question* — what it decides, what each option does differently, what the tradeoff is — using what you already know. Do **not** re-fire the decision, re-emit the same question, or re-call AskUserQuestion at the end. Do **not** reflexively go run more tool calls; answer from what's already in context, and only investigate if a *specific* fact is genuinely missing — in which case name that fact and explain why it's needed. A context request is evidence I under-framed the question: the fix is to explain it, never to repeat it.
  - If you mark an option `(Recommended)`, justify it. Say briefly *why* you prefer it and what the main tradeoff is against the next-best alternative. An unjustified recommendation is just a tag — it tells me nothing about your reasoning and I can't agree or push back on it.
  - Keep options few and concrete. If you're reaching for four options with subtle distinctions, the problem is under-framed — do another pass yourself and ask a narrower question. Two well-chosen options beat four mushy ones.
  - Code review is a primary use case. When reviewing a diff or PR, surface each finding as its own question with concrete action options (e.g. "fix now", "leave as-is", "defer to follow-up") rather than dumping a prose list of issues for me to triage. This turns review into a sequence of decisions I can actually act on. Same per-question framing rule applies: each finding needs its own explanation of *what* you found, *why* it matters, and *why* you're recommending the action you are.
  - **This convention outranks any skill's local apply/skip instruction.** When a skill (`/simplify`, `/simplify-with-analysis`, `/address-review-comments`, or any built-in review pass) tells you to fix or skip findings on your own — e.g. "fix each one directly, note the skip rather than arguing with it" — that does not override this rule. Specifically: a decision *not* to act on a finding — skip, keep-as-is, mark false-positive, dispute, "acceptable, moving on" — must come to me as a decision before you finalize, not be recorded as a mid-stream log note I never see. Applying a clearly-genuine fix is fine; declining to act on feedback is mine to exercise. A skill's "proceed autonomously" framing never wins against this.
