---
name: qa
description: Bring up a remote-devbox QA session for the current payaus worktree — one command replaces four terminals (tunnel, server, worker, webpack), plus a QA checklist from the PR and a suggested test organisation. Use when the user invokes /qa, says "QA this PR", "set up the devbox for QA", or "spin up QA for this branch".
---

# /qa — remote-devbox QA bring-up

Orchestrates `qa-up` (`~/.local/bin/qa-up`) and layers on the parts that need judgment: extracting QA steps from the PR and finding a good test organisation.

This skill intentionally targets the **remote dev box** — an exception to the prefer-native-dev default. Use it when QA needs the shared, prod-scrubbed dataset.

## Steps

Run steps 1–3 first, then 4 in parallel with 5 (PR analysis needs no devbox).

### 1. Establish context

`git rev-parse --show-toplevel` and current branch. qa-up infers the worktree from cwd; only pass a name explicitly if the user asked for a different worktree.

### 2. Sync the branch

Run `git town sync` in the worktree first, so QA runs against code that's current with master (the shared dev DB is migrated as master merges). If sync stops on a conflict, surface it and stop — don't force past it.

### 3. Launch qa-up

```
qa-up --no-attach
```

Run via Bash with `run_in_background: true` — full bring-up takes 5–15 minutes. **Never start a second copy**; if qa-up reports the session already running, skip to step 5.

If it reports "switched from <other>", relay that to the user — their previous QA session was torn down.

### 4. QA checklist from the PR

- `gh pr view --json number,title,body,url` (from the worktree — infers the PR from the branch).
- Extract the section under a `## QA`, `## Testing`, or `## How to test` heading (payaus has no PR template; `## QA` is the common convention).
- No such section → derive concrete QA steps from the diff (follow the PR-diff-size workflow in the global CLAUDE.md § "Analyzing PR changes"). Say the checklist is derived, not authored.
- No PR for the branch → say so and derive steps from `git log`/diff against master.

### 5. Wait for readiness

Poll the background shell's output. Success is the line:

```
QA_READY url=<app url> session=qa-<worktree>
```

On failure, qa-up prints the failing tab's last output — relay it. Common cases: dev box stopped ("Try 'bin/dev start'"), or the tunnel tab waiting on interactive AWS SSO auth (tell the user to attach and complete it: `qa-up attach <worktree>`).

### 6. Test-org discovery

After QA_READY, follow the dev-console contract (`payaus/.claude/skills/dev-console/SKILL.md` — `bin/dev runner`, strictly read-only, run from `~/programming/payaus`).

Start from:

```ruby
Organisation.where(is_active: true).where.not(demo: true).where(country: "Australia").order(updated_at: :desc)
```

Refine by what the diff touches — pick an org with real data on the changed models (e.g. rostering change → orgs with recent rosters; timesheet change → recent timesheets). Return 1–3 candidates with name + id.

### 7. Report

- QA checklist (numbered)
- Test org name + id
- App URL (from the QA_READY line)
- `qa-up attach <worktree>` to watch the tabs
- `qa-up --down` to tear down when finished
