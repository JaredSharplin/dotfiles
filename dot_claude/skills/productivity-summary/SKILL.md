---
name: productivity-summary
description: >
  Periodic work check-in. Runs the collector to snapshot git commits/branch
  movement, GitHub PR and review activity, and Claude session activity across all
  worktrees since the last tick, then prints a tight terminal summary, flags stalled
  work, and fires a macOS notification. Records each snapshot to
  ~/.local/share/productivity/<date>.jsonl for end-of-day reflection. Use when the
  user invokes /productivity-summary, asks "what have I done", wants a productivity
  check-in, or — the intended use — runs it on a timer via `/loop 30m /productivity-summary`.
---

# Productivity check-in

A tick of a running work log. Meant to fire every ~30 min under `/loop`. Each tick: gather a
snapshot, narrate what moved, nudge if something's drifting, notify.

Keep it fast and cheap — the collector does all gathering and recording; your job is the narration
and the nudge, nothing else. Do NOT gather git/GitHub/session data yourself; read it from the
collector's JSON.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

This appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as
JSON on stdout. Parse that JSON — it has `since` (start of this interval), `git`, `github`, and
`sessions`.

## Step 2 — summarize (terminal)

Print a short summary, in this shape:

- One line: interval window (`since` → now) and headline totals — commits this interval, PRs
  authored/merged today, reviews given today.
- Git: per-repo commit lines that have `count > 0` (`repo/branch: N commits, +ins/-del`).
- Sessions: one line per worktree from `sessions`, newest/most-active first —
  `<worktree> (<branch>): N turns, tools…, advancing|idle`. Use the `advancing` flag and `titles`.

Keep the whole thing scannable — a dozen lines at most. Omit empty sections rather than printing
"nothing".

## Step 3 — nudge

Add one or two short "on track?" observations grounded in the data:

- A worktree/branch with a session active but `advancing: false` (turns but no edits/commits) — may
  be stuck or exploring.
- Focus scatter — many worktrees touched in one interval.
- A day total that's flat across several ticks (compare to earlier records in today's log if useful).

If everything looks healthy, say so in one line. Don't invent problems.

## Step 4 — notify

Fire one macOS notification with a one-line headline and the top nudge. Keep the body under ~120
chars and escape any double quotes:

```bash
osascript -e 'display notification "3 commits · 1 PR merged · mds-feedback advancing" with title "Productivity check-in" subtitle "10:00–10:30"'
```

That's the whole tick. End the turn — under `/loop`, the next tick fires on schedule.
