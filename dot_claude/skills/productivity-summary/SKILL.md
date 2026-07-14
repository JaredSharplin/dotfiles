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
job is to keep the developer moving through the pipeline: call the period as it is, then point at the
one thing that advances a PR to its next stage. Be blunt. This is a coach, not a diary.

**The finish line is shipping to customers** — a merged PR labelled `feature` or `bug`. But shipping
runs through a pipeline, and skipping a stage isn't speed:

```
draft (WIP)  →  QA  →  ready-for-review  →  review  →  merged / shipped
```

Two things count as real progress, and both are wins:

- **Shipped** (`github.shipped`, `customer_facing: true`) — a customer-facing PR merged. The finish line.
- **QA cleared** (`github.qa_completed`) — a PR that flipped draft→ready this period. QA is
  time-consuming, invisible in raw git data, and mandatory; going ready is its visible outcome, so
  bank it like a win, not a footnote.

Everything else — WIP commits, reviews given, internal/refactor merges, session churn — is motion,
not progress. **The enemy is a PR stuck in a stage, not a PR that isn't merged yet.** Never push a
draft toward review or merge — a draft's next step is QA, full stop. And *only the developer* flips a
PR to ready-for-review, by hand, after QA — you never mark a PR ready and never offer to.

Keep it fast and cheap — the collector does all gathering and recording; your job is the verdict and
the push. Do NOT gather data yourself; read the collector's JSON.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

Appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as JSON.
Everything below describes **this interval**. Parse the JSON — `window` (local-time `HH:MM–HH:MM`
label; use it verbatim, don't reformat `since`/`ts`, which are UTC), `github.shipped` (merged PRs,
each with `customer_facing`), `github.qa_completed` (flipped draft→ready this period),
`github.in_flight` (open PRs, each with `isDraft`), `github.reviews_given`, `git.commits`, `sessions`.

## Step 2 — the verdict (this period only)

No day totals, no "so far today" — only what moved this interval. Lead with the scoreboard, ordered
by what matters:

1. **Shipped** — the finish line. Customer-facing merges first (`customer_facing: true`):
   `🚢 SHIPPED: #N <title>`. Non-customer-facing merges after, one line, flagged internal.
2. **QA cleared** — `qa_completed`: `✅ QA'd & ready: #N <title>`. A real win; the gate is passed.
3. **In flight** — `in_flight` PRs by stage (`isDraft`): a draft is `#N <title> (draft — in QA)`, a
   non-draft is `#N <title> (ready — awaiting review)`. A ready PR sitting unmerged is a target; a
   draft is legitimately mid-pipeline, not a failure.
4. **Motion** — brief, clearly subordinate: reviews given, commits per repo/branch with `count > 0`,
   active worktrees (`<worktree>: N turns, advancing|STALLED`). Effort, not progress.

If nothing shipped and nothing cleared QA, open with it and don't dress it up —
`⛔ Nothing shipped or QA'd in <window>.` Scannable — a dozen lines at most. Omit empty sections.

## Step 3 — the push

End every tick with a verdict and exactly one directive — the single highest-leverage move to
advance a PR one stage in the next 30 minutes. Match the directive to the stage; **never tell the
developer to get a draft reviewed or to skip QA:**

- A **ready** (non-draft) PR unmerged → review/merge is the move: `#N passed QA — get eyes on it and land it.`
- A **draft** being actively worked → respect the QA: `#N is in QA. Finish it and flip it to ready when it passes.`
- A **draft** sitting untouched → `#N has stalled in draft — QA it and get it ready, or it'll rot.`
- Sprawl across worktrees, nothing advancing → `3 worktrees touched, nothing moved a stage. Pick one — <branch> is closest — and drive it.`
- Effort sunk into internal/refactor while customer work sits → `That's polish, not shipping. <feature-branch> is what customers are waiting on.`
- A worktree `advancing: false` → `<worktree> has stalled — N turns, no edits. Unblock it or drop it.`

If a PR shipped or cleared QA this period, bank it in one line (`That's the win. Next: …`) and still
point at what's next. Don't invent a crisis — but never end on a shrug. Always leave one clear next
action, and never one that skips a pipeline stage.

## Step 4 — notify

One macOS notification, headline led by the verdict and carrying the directive. Punchy, under ~120
chars, escape double quotes:

```bash
# shipped:
osascript -e 'display notification "🚢 Shipped #4821. Next: land #4830, it'\''s ready." with title "Productivity check-in" subtitle "<window>"'
# QA cleared:
osascript -e 'display notification "✅ #4830 cleared QA. Next: get it reviewed." with title "Productivity check-in" subtitle "<window>"'
# stuck in draft:
osascript -e 'display notification "⛔ 0 shipped. #4830 in QA — finish it and mark ready." with title "Productivity check-in" subtitle "<window>"'
```

That's the whole tick. End the turn — under `/loop`, the next tick fires on schedule.
