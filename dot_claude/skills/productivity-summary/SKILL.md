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

A **momentum check on the last ~30 minutes only** — nothing cumulative. Fires under `/loop`. Your
job is to keep the developer moving: call the period as it is, then point at the one thing that gets
work shipped next. Be blunt. This is a coach, not a diary.

**Only one thing counts: shipping to customers.** A merged PR labelled `feature` or `bug` is a win.
Everything else — WIP commits, reviews, internal/refactor merges, session churn — is motion, not
progress, and you say so. Half an hour with nothing shipped is not neutral; name it. Do not soften a
flat period with busywork stats or congratulate effort that didn't ship anything.

Keep it fast and cheap — the collector does all gathering and recording; your job is the verdict and
the push. Do NOT gather data yourself; read the collector's JSON.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

Appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as JSON.
Everything below describes **this interval**. Parse the JSON — `window` (local-time `HH:MM–HH:MM`
label for this interval; use it verbatim, don't reformat `since`/`ts`, which are UTC), `github.shipped`
(merged PRs, each with `customer_facing`), `github.in_flight`, `github.reviews_given`, `git.commits`,
`sessions`.

## Step 2 — the verdict (this period only)

No day totals, no "so far today" — only what moved this interval. Lead with the scoreboard, ordered
by what matters:

1. **Shipped** — the only line that earns a win. Customer-facing merges first (`customer_facing:
   true`): `🚢 SHIPPED: #N <title>`. Non-customer-facing merges after, one line, flagged internal.
   If `shipped` is empty, open with it and don't dress it up — `⛔ Nothing shipped in <window>.`
2. **In flight** — `in_flight` PRs and how close they are (`isDraft`): `#N <title> (draft|ready)`.
   A ready PR sitting unmerged is a target, not an achievement — treat it that way.
3. **Motion** — brief, clearly subordinate: reviews given, commits per repo/branch with `count > 0`,
   active worktrees (`<worktree>: N turns, advancing|STALLED`). This is effort, not progress.

Scannable — a dozen lines at most. Omit empty sections; never pad.

## Step 3 — the push

End every tick with a verdict and exactly one directive — the single highest-leverage move to get
something shipped in the next 30 minutes. Name the PR/branch. Be direct:

- Nothing shipped but a PR is ready → `Ship #N now. It's ready and it's the win.`
- Nothing shipped, work sprawled across worktrees → call the scatter out and pick the one to close:
  `3 worktrees touched, 0 merged. Pick one — <branch> is closest — and land it.`
- Effort sunk into internal/refactor while customer work stalls → `That's polish, not shipping.
  <feature-branch> is what customers are waiting on.`
- A worktree `advancing: false` → `<worktree> has stalled — N turns, no edits. Unblock it or drop it.`

If a customer-facing PR shipped this period, bank it in one line (`That's the win. Next: …`) and
still point at what's next. Don't invent a crisis — but never end on a shrug. Always leave one clear
next action.

## Step 4 — notify

One macOS notification, headline led by the verdict and carrying the directive. Punchy, under ~120
chars, escape double quotes:

```bash
osascript -e 'display notification "🚢 Shipped #4821. Next: land #4830, it'\''s ready." with title "Productivity check-in" subtitle "<window>"'
# nothing shipped:
osascript -e 'display notification "⛔ 0 shipped, 3 WIP commits. Land #4830 now — it'\''s ready." with title "Productivity check-in" subtitle "<window>"'
```

That's the whole tick. End the turn — under `/loop`, the next tick fires on schedule.
