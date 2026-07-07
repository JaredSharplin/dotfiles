# Payaus Native Local Development (puma-dev)

Run the payaus Rails app natively on macOS using puma-dev. Supports multiple worktrees simultaneously for parallel Claude QA via Chrome MCP.

## Quick reference

```bash
# Set up any payaus directory for native dev
# <name> becomes the .test domain and the puma-dev symlink (~/.puma-dev/<name>)
~/.config/payaus-native-dev/setup-worktree.rb payaus     # main repo → https://payaus.test
~/.config/payaus-native-dev/setup-worktree.rb slot-1     # worktree  → https://slot-1.test

# Ensure services (postgres, memcached, minio, puma-dev) are running
~/.config/payaus-native-dev/ensure-services.sh

# List / teardown
~/.config/payaus-native-dev/setup-worktree.rb --list
~/.config/payaus-native-dev/setup-worktree.rb --teardown slot-1

# Compile assets and visit
~/.config/payaus-native-dev/watch          # long-running: compile on every change
~/.config/payaus-native-dev/watch --once   # one-shot: compile once and exit
# https://payaus.test or https://slot-1.test
```

## Prerequisites (one-time)

```bash
brew tap puma/puma && brew install puma-dev minio minio-mc
brew install --cask puppetlabs/puppet/puppet-agent-8
sudo puma-dev -setup    # creates /etc/resolver/test for .test DNS
puma-dev -install       # installs LaunchAgent on ports 80/443
```

## Architecture

```
Browser (https://slot-1.test)
  → puma-dev (port 80/443, launchd socket activation)
    → DNS: /etc/resolver/test → 127.0.0.1
    → TLS: auto-generated per domain
    → Static: serves public/assets/webpack/* from disk
    → Proxy: ~/.puma-dev/slot-1 symlink → worktree → Rails
```

No nginx. puma-dev handles DNS, TLS, static files, and Rails proxying.

## Files in this directory

| File | Deployed to | Purpose |
|------|-------------|---------|
| `env.template` | `<worktree>/.pumaenv` | Environment variables for native dev |
| `initializer.rb` | `<worktree>/config/initializers/99_local_native_dev.rb` | Suppresses MigrationTimings file mutations (host allowlisting + assume_ssl now live in master's development.rb) |
| `setup-worktree.rb` | (run directly) | Deploys .pumaenv + initializer + puma-dev symlink |
| `ensure-services.sh` | (run directly) | Starts postgres/memcached/minio/puma-dev via Puppet |
| `restart` | (run directly) | Cleanly restart puma-dev apps + remove stale sockets |
| `watch` | (run directly) | Compile assets (`--once` to exit after one compile) |
| `rails` | (run directly) | `bin/rails` with .pumaenv + local-DB safety checks |
| `lib.rb` | (required by wrappers) | Shared .pumaenv loader + mise toolchain provisioning + yarn-install skip logic |
| `puppet/` | (used by ensure-services.sh) | Puppet manifests for service management |

Deployed files are gitignored in payaus: `.pumaenv` via both master's own `.gitignore` (added by #45524) and `~/.global_gitignore`; `99_local_native_dev.rb` via `~/.global_gitignore` only (master does not ignore it).

## Decision log

### Why puma-dev (not Docker, not nginx)

Docker local (`bin/docker-local/`) works but uses ~8GB RAM. Running multiple instances for parallel worktrees is impractical. The remote dev server (`bin/dev`) only works from the main payaus directory, not worktrees.

puma-dev runs as a lightweight LaunchAgent, auto-boots Rails per domain via symlinks, handles TLS and DNS, and supports unlimited concurrent `.test` domains with minimal overhead.

Based on rhys117's PR #45524 and GitHub discussion #46237. That PR **merged on 2026-06-29** in trimmed form — an opt-in, unsupported ("as-is", not maintained by the PIT team) native path; Docker / `bin/dev` remains the officially supported workflow. This chezmoi setup predates the merge and intentionally diverges from it (see [Relationship to the merged upstream](#relationship-to-the-merged-upstream-45524) below).

### Why no nginx

Rhys' original (pre-merge) PR used nginx to proxy `/assets/webpack/` to webpack-dev-server and everything else to puma-dev; the merged #45524 dropped nginx too. We use `webpack --watch` instead of `webpack-dev-server`, which writes assets to disk (`public/assets/webpack/`, enabled by `writeToDisk: true` in webpack config). puma-dev serves static files from `public/` directly, so nginx is unnecessary.

Trade-off: no hot module replacement (HMR). Changes require a browser refresh. Fine for Claude QA.

### Why BOOT_WITHOUT_SECRETS (not modifying tracked files)

**This is the most critical design decision.**

The vault loader (`config/variables/vault/loader.rb`) runs at boot via `config/boot.rb` → `config/variables.rb`. In development, it loads `config/variables/staging/ap-southeast-2/shared.yml` which contains:

```yaml
DEV_DATABASE_HOST: payaus.writer.tt-dev-apac.payaus.adnat.co  # SHARED REMOTE DB
```

Its `assign_env_var` uses `ENV[var] = value` (overwrite) in development **unless `IN_CONTAINER=true`**, in which case it uses `ENV[var] ||= value` (existing env wins). We don't set `IN_CONTAINER`, so without a guard the overwrite branch would replace the local env vars set via `.pumaenv` with remote database credentials. (Master's merged native setup takes the `IN_CONTAINER` branch instead; we skip the vault entirely — see the chosen approach below.)

**Approaches evaluated and rejected:**

1. **Modify `vault/loader.rb` to check `RUNNING_LOCAL_NATIVE_ENV`** — would make it use `||=` (preserve existing). Works but requires merging to master (not permitted) or cherry-picking per worktree (tedious).

2. **`git update-index --assume-unchanged`** — hides local file modifications from git. Rejected because:
   - Branch switches/rebases silently overwrite the patches
   - Both `development.rb` and `loader.rb` are frequently modified upstream
   - Silent loss of safety-critical patches is unacceptable
   - The vault change is especially dangerous — losing it means `bin/rails db:drop` targets the shared remote database

3. **Rails initializer for vault override** — initializers run after the vault, so they can't prevent the overwrite. The vault runs at `config/boot.rb` time, before any initializers.

**Chosen approach: `BOOT_WITHOUT_SECRETS=true`**

`config/variables.rb` line 8: `return if ENV["BOOT_WITHOUT_SECRETS"]`. This early-exit skips the vault entirely. Since:
- The vault's encrypted secrets fail to decrypt locally anyway (no AWS credentials)
- All required env vars are in `.pumaenv`
- The only plaintext vars from the vault we'd miss are external service URLs that don't work locally

This is the safest option — the vault never loads, never touches env vars, no risk of the vault pointing Rails at a remote database. (One non-vault path can still inject env — see the caveat below.)

The `setup-worktree.rb` script verifies `BOOT_WITHOUT_SECRETS=true` is present in every deployed `.pumaenv`.

**Caveat introduced by the #45524 merge.** Master's `config/boot.rb` now runs `Dotenv.overload(".env.local")` whenever `RUNNING_LOCAL_NATIVE_ENV=true` (which every `.pumaenv` sets) and `RAILS_ENV != production`. This runs **before** the vault and is **not** gated by `BOOT_WITHOUT_SECRETS`, so a stray `.env.local` in a worktree would override `.pumaenv` values — including `DEV_DATABASE_HOST` — and `BOOT_WITHOUT_SECRETS` would not stop it. We use `.pumaenv`, not `.env.local`; keep worktrees free of any `.env.local` file.

### Why chezmoi (not in the payaus repo)

Setup files (wrappers, Puppet manifests) can't be committed to payaus master (not permitted), and committing the deployed artifacts isn't viable either:
- Gitignored files aren't recoverable from git
- The initializer (`99_local_native_dev.rb`) isn't ignored by master's `.gitignore`, so it would otherwise show as untracked on every branch

Chezmoi provides version control, cross-machine sync, and recoverability without touching the payaus repo. Deployed files are gitignored via `~/.global_gitignore` (also tracked by chezmoi); master additionally ignores `.pumaenv` in its own `.gitignore` since #45524.

### Why shared database (not per-worktree)

All worktrees share `payaus_development` on localhost. This is safe because:
- Job queues are isolated: `APP_HOST_URL` becomes the delayed_job queue name per worktree
- Sessions are separate: different `.test` domains get different cookies
- Data conflicts are theoretically possible but unlikely for QA purposes

Per-worktree databases were considered but add seeding complexity (DemoAccountCreator takes ~30 min per DB).

### Why puma-dev on ports 80/443 (not 9280/9283)

Rhys' original (pre-merge) PR used 9280/9283 because nginx proxied from 443; the merged #45524, having dropped nginx, uses 80/443 as here. Without nginx, the app URL must match `APP_HOST_URL=payaus.test` (no port). Rails redirects, CSRF tokens, and cookies all reference the host without a port.

`puma-dev -install` defaults to 80/443. launchd handles privileged port binding on macOS — no root needed. Using non-default ports was a mistake in initial setup that caused `https://payaus.test` (port 443) to not connect.

### Toolchain: node + yarn via mise (not corepack)

Payaus pins its toolchain in `mise.toml` (e.g. `node="24"`, `yarn="4.16.0"` as of #53678). Since mise already manages node and ruby on this machine, mise is also the yarn provider — `watch` runs `mise install` to provision whatever the repo declares, then invokes tools via `mise exec`. No corepack involved (payaus's own `bin/yarn` shells out to `corepack yarn`, but that's for CI/Docker; on a mise machine the `mise.toml` yarn pin is the intended path).

Two non-obvious reasons the wrapper invokes tools through `mise exec` rather than a bare `yarn`/`npx`:

1. **`mise activate`, not shims.** The shell computes PATH at `cd` time. A yarn version that wasn't installed when the shell entered the worktree won't be on PATH after `watch` installs it mid-run — a bare `yarn` would fall through to Homebrew's classic yarn (1.x) and choke on the Yarn-4 `.yarnrc.yml`/lockfile. `mise exec` re-resolves against the freshly-installed versions. This was the exact failure when master bumped 1.22.22 → 4.16.0.
2. **Self-healing on sync.** Provisioning lives in the `watch` path (`lib.rb`), not just `setup-worktree.rb`, so a `git town sync` that pulls a future toolchain bump is picked up on the next `watch` without re-running setup.

Yarn 4 note: the install command is `yarn install --immutable` (`--frozen-lockfile` was removed in Yarn 4). The `.yarnrc.yml` uses `nodeLinker: node-modules`, so `node_modules/` still exists and the `npx webpack` + yarn.lock-mtime stamp logic are unaffected.

### Why webpack --watch (not webpack-dev-server)

`webpack-dev-server` (`yarn serve`) runs on port 8081 — one instance per machine. Multiple worktrees would contend for that port, and puma-dev can't route each domain's assets to a per-worktree dev-server.

`webpack --watch` instead writes compiled assets to each worktree's own `public/assets/webpack/` (via `writeToDisk: true` in `config/webpack/development.babel.js`); puma-dev serves them as static files, so every worktree builds independently with no shared port. The `watch` wrapper invokes `npx webpack --watch` directly through `mise exec` — no `package.json` script is involved.

This is a deliberate divergence from the merged #45524, which uses `yarn serve` (the 8081 singleton) and so supports only one active app at a time.

## Relationship to the merged upstream (#45524)

PR #45524 merged on 2026-06-29 (trimmed, opt-in, unsupported). Master now ships the following, all gated behind `RUNNING_LOCAL_NATIVE_ENV` / `IN_CONTAINER` / `DEV_CATCH_EMAIL` and inert in CI/staging/production:

- `docs/local-native-setup.md`, `.env.template`, the `dotenv` gem, and `.pumaenv` in `.gitignore`
- app-code touchpoints: `.env.local` loading (`config/boot.rb`), `.test` host allowlisting + `assume_ssl` (`config/environments/development.rb`), and mailpit email catching (`config/initializers/02_configuration/mail.rb`)
- Puppet manifests under `useful_scripts/puppet/`

This chezmoi setup predates the merge and intentionally diverges:

- **`BOOT_WITHOUT_SECRETS`**, not `IN_CONTAINER` — skips the vault entirely rather than feeding it env vars (see the safety decision above)
- **mise**, not nvm + global yarn — correct for the repo's Yarn-4 pin
- **multi-worktree orchestration** (`setup-worktree.rb`, per-domain symlinks) — master is single-app
- **`webpack --watch`**, not `yarn serve` — independent per-worktree builds

The two coexist cleanly: because master's touchpoints key off the same `RUNNING_LOCAL_NATIVE_ENV` marker this setup already sets, the deployed initializer now carries only the `MigrationTimings` no-op (master's `development.rb` owns the host/`assume_ssl` half).

The old `feature/native-local-dev` branch (last touched 2026-04-07) is abandoned and superseded by the above — nothing here depends on it.

## Database seeding

```bash
source .pumaenv
bin/rails db:create && bin/rails db:schema:load && bin/rails db:seed
```

**ALWAYS source .pumaenv first.** Without it, `BOOT_WITHOUT_SECRETS` is unset, the vault loads remote credentials, and database commands target the shared dev server.

Login credentials (from seeds):
- Sysadmin: `info@tanda.co` / `password1`
- Demo org: `demoaccount+1@tanda.co` / `password123`

## Running from an agent / background task

- For "compile once, then verify in the browser" use **`watch --once`**.
  It exits 0/non-zero when the compile finishes and is the right primitive
  for single-session flows.
- Without `--once`, `watch` never exits. If you launch it via a background
  task, do **not** pipe stdout through `tail`/`head`/`grep` without
  `--line-buffered` — pipe buffering will hide all output until the
  process dies.
- If you do need to stream long-running `watch`, the reliable grep target
  for a Monitor filter is webpack's own end-of-compile line, e.g.
  `"compiled (successfully|with \d+ (errors?|warnings?)) in \d+ ms"`.

## Troubleshooting

### "Connection refused" to remote IP

`BOOT_WITHOUT_SECRETS` is not set. Source `.pumaenv` before running Rails commands:
```bash
source .pumaenv && echo $BOOT_WITHOUT_SECRETS  # must print "true"
```

### Pending migrations

The local DB schema may be behind master. Reset with:
```bash
source .pumaenv && DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:drop db:create db:schema:load db:seed
```

### puma-dev not resolving .test domains

```bash
cat /etc/resolver/test  # should show nameserver 127.0.0.1
```
If missing: `sudo puma-dev -setup`

### App unresponsive after restart / "There is already a server bound to" socket error

puma-dev's phased restart (`touch tmp/restart.txt`) has a race condition: the old process may not clean up its Unix socket before the new process tries to bind. Use the restart script instead:
```bash
~/.config/payaus-native-dev/restart        # stop all apps + clean sockets
~/.config/payaus-native-dev/restart slot-1  # clean sockets for slot-1 only
```

### PostgreSQL "role postgres does not exist"

Homebrew postgres uses `$USER` as superuser, not `postgres`. The Puppet `postgresql.pp` manifest handles this by trying both.
