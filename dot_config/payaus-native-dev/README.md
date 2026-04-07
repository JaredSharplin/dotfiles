# Payaus Native Local Development (puma-dev)

Run the payaus Rails app natively on macOS using puma-dev. Supports multiple worktrees simultaneously for parallel Claude QA via Chrome MCP.

## Quick reference

```bash
# Set up a worktree for native dev
~/.config/payaus-native-dev/setup-worktree.rb payaus     # main repo
~/.config/payaus-native-dev/setup-worktree.rb slot-1     # worktree

# Ensure services (postgres, memcached, minio, puma-dev) are running
~/.config/payaus-native-dev/ensure-services.sh

# List / teardown
~/.config/payaus-native-dev/setup-worktree.rb --list
~/.config/payaus-native-dev/setup-worktree.rb --teardown slot-1

# In a worktree: compile assets and visit
source .pumaenv && yarn watch
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
| `initializer.rb` | `<worktree>/config/initializers/99_local_native_dev.rb` | Adds .test to Rails allowed hosts |
| `setup-worktree.rb` | (run directly) | Deploys .pumaenv + initializer + puma-dev symlink |
| `ensure-services.sh` | (run directly) | Starts postgres/memcached/minio via Puppet |
| `puppet/` | (used by ensure-services.sh) | Puppet manifests for service management |

Deployed files are gitignored in payaus via `~/.global_gitignore`.

## Decision log

### Why puma-dev (not Docker, not nginx)

Docker local (`bin/docker-local/`) works but uses ~8GB RAM. Running multiple instances for parallel worktrees is impractical. The remote dev server (`bin/dev`) only works from the main payaus directory, not worktrees.

puma-dev runs as a lightweight LaunchAgent, auto-boots Rails per domain via symlinks, handles TLS and DNS, and supports unlimited concurrent `.test` domains with minimal overhead.

Based on rhys117's unmerged PR #45524 and GitHub discussion #46237. The PR was closed (not merged) because the team chose to support Docker as the official local path. Native dev is unsupported/opt-in.

### Why no nginx

Rhys' original PR used nginx to proxy `/assets/webpack/` to webpack-dev-server and everything else to puma-dev. We use `webpack --watch` instead of `webpack-dev-server`, which writes assets to disk (`public/assets/webpack/`, enabled by `writeToDisk: true` in webpack config). puma-dev serves static files from `public/` directly, so nginx is unnecessary.

Trade-off: no hot module replacement (HMR). Changes require a browser refresh. Fine for Claude QA.

### Why BOOT_WITHOUT_SECRETS (not modifying tracked files)

**This is the most critical design decision.**

The vault loader (`config/variables/vault/loader.rb`) runs at boot via `config/boot.rb` → `config/variables.rb`. In development, it loads `config/variables/staging/ap-southeast-2/shared.yml` which contains:

```yaml
DEV_DATABASE_HOST: payaus.writer.tt-dev-apac.payaus.adnat.co  # SHARED REMOTE DB
```

It uses `ENV[var] = value` (unconditional overwrite), meaning any local env vars set via `.pumaenv` get replaced with remote database credentials.

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

This is the safest option — the vault never loads, never touches env vars, no risk of connecting to remote databases.

The `setup-worktree.rb` script verifies `BOOT_WITHOUT_SECRETS=true` is present in every deployed `.pumaenv`.

### Why chezmoi (not in the payaus repo)

Setup files can't be committed to payaus master (not permitted). They can't be gitignored in the repo because:
- Gitignored files aren't recoverable from git
- Other branches don't have the `.gitignore` entries

Chezmoi provides version control, cross-machine sync, and recoverability without touching the payaus repo. Deployed files (`.pumaenv`, initializer) are gitignored via `~/.global_gitignore` (also tracked by chezmoi).

### Why shared database (not per-worktree)

All worktrees share `payaus_development` on localhost. This is safe because:
- Job queues are isolated: `APP_HOST_URL` becomes the delayed_job queue name per worktree
- Sessions are separate: different `.test` domains get different cookies
- Data conflicts are theoretically possible but unlikely for QA purposes

Per-worktree databases were considered but add seeding complexity (DemoAccountCreator takes ~30 min per DB).

### Why puma-dev on ports 80/443 (not 9280/9283)

Rhys' PR used 9280/9283 because nginx proxied from 443. Without nginx, the app URL must match `APP_HOST_URL=payaus.test` (no port). Rails redirects, CSRF tokens, and cookies all reference the host without a port.

`puma-dev -install` defaults to 80/443. launchd handles privileged port binding on macOS — no root needed. Using non-default ports was a mistake in initial setup that caused `https://payaus.test` (port 443) to not connect.

### Why webpack --watch (not webpack-dev-server)

`webpack-dev-server` (`yarn serve`) runs on port 8081. Multiple worktrees would need separate ports, and nginx/puma-dev would need to route each domain's assets to the right port.

`webpack --watch` writes compiled assets to `public/assets/webpack/` (enabled by `writeToDisk: true` in `config/webpack/development.babel.js`). puma-dev serves these as static files. Each worktree has its own `public/` directory, so no port conflicts.

The `yarn watch` script was added to `package.json` on the `feature/native-local-dev` branch.

## Payaus branch: feature/native-local-dev

Contains:
- `.gitignore` entries for deployed files
- `package.json` `yarn watch` script
- `docs/local-native-setup.md` — user-facing setup documentation

This branch is documentation/reference only. The actual setup lives here in chezmoi.

## Database seeding

```bash
source .pumaenv
bin/rails db:create && bin/rails db:schema:load && bin/rails db:seed
```

**ALWAYS source .pumaenv first.** Without it, `BOOT_WITHOUT_SECRETS` is unset, the vault loads remote credentials, and database commands target the shared dev server.

Login credentials (from seeds):
- Sysadmin: `info@tanda.co` / `password1`
- Demo org: `demoaccount+1@tanda.co` / `password123`

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

### PostgreSQL "role postgres does not exist"

Homebrew postgres uses `$USER` as superuser, not `postgres`. The Puppet `postgresql.pp` manifest handles this by trying both.
