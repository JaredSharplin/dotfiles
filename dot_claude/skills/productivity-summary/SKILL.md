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

A check-in on the **most recent period only** — what happened since the last tick, nothing
cumulative. Meant to fire every ~30 min under `/loop`.

**The metric that matters is shipping to customers.** A merged PR labelled `feature` or `bug` is the
signal; everything else (WIP commits, reviews, internal/refactor merges, session churn) is
supporting work and ranks below it. Lead with what shipped; if nothing shipped, that's itself the
headline, not a gap to paper over with busywork stats.

Keep it fast and cheap — the collector does all gathering and recording; your job is the narration
and the nudge. Do NOT gather data yourself; read the collector's JSON.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

Appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as JSON.
Everything below describes **this interval** (`since` → `ts`). Parse the JSON — `github.shipped`
(merged PRs, each with `customer_facing`), `github.in_flight`, `github.reviews_given`, `git.commits`,
`sessions`.

## Step 2 — summarize (this period only)

No day totals, no "so far today" — only what moved this interval. Order by importance:

1. **Shipped** — lead here. Customer-facing merges first (`customer_facing: true`):
   `🚢 Shipped: #N <title>`. Any non-customer-facing merges after, one line, labelled internal.
   If `shipped` is empty, say so plainly in one line — "Nothing shipped this period."
2. **In flight** — `in_flight` PRs that moved (draft vs ready via `isDraft`): `#N <title> (draft|ready)`.
3. **Supporting** — brief, subordinate: reviews given (`reviews_given`), commits per repo/branch
   with `count > 0`, and active worktrees from `sessions` (`<worktree>: N turns, advancing|idle`).

Keep it scannable — a dozen lines at most. Omit empty sections.

## Step 3 — nudge

One or two short observations, judged against shipping:

- Nothing shipped while lots of activity piled up (commits, turns, open PRs) — flag it.
- Effort concentrated on non-customer-facing work (internal/refactor) — note it's not moving the
  main needle, without judgement.
- A worktree active but `advancing: false` — may be stuck or exploring.

If a customer-facing PR shipped, say so and move on — don't manufacture a concern.

## Step 4 — notify

One macOS notification, headline led by shipping. Body under ~120 chars, escape double quotes:

```bash
osascript -e 'display notification "🚢 1 customer-facing shipped · 2 PRs in flight" with title "Productivity check-in" subtitle "10:00–10:30"'
# nothing shipped:
osascript -e 'display notification "Nothing shipped · 3 WIP commits, 1 review" with title "Productivity check-in" subtitle "10:00–10:30"'
```

That's the whole tick. End the turn — under `/loop`, the next tick fires on schedule.
