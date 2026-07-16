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

A check-in on the last ~30 minutes only — not the whole day. Runs under `/loop`. Your job: say
plainly what happened, then say the one next thing worth doing.

**Write like a person talking.** Short, plain sentences. No metaphors, no invented phrases, no
jargon. Do not say "gate", "stage", "pipeline", "momentum", "drive it", "land it", "the finish
line", "motion vs progress", "under your hands", "scatter". Say the plain thing instead: "merge it",
"review it", "finish testing it", "you didn't finish anything". If a sentence needs decoding,
rewrite it.

What actually counts as work finished:

- **A PR merged for customers** — a merged PR labelled `feature` or `bug`. This is the main thing.
- **A PR you finished and marked ready for review** — a PR that went from draft to ready this period
  (`github.qa_completed`). Testing a PR takes real time and doesn't show up in commit data, so
  marking it ready is how we see that work happened. It counts — say so.

Everything else — commits on unfinished work, reviews you left on other PRs, internal or refactor
merges, Claude session activity — is work in progress, not finished. Say that plainly, without
putting it down.

Two rules about drafts:

- A draft PR is not finished being tested. Its next step is testing, then marking it ready. Never
  tell the developer to get a draft reviewed or merged.
- Marking a PR ready happens after testing, on the developer's explicit request — not something to
  do or suggest from this summary.

The collector does all the data gathering; you just read its JSON and talk. Don't gather data yourself.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

Appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as JSON.
Everything below is about **this period only**. Read the JSON — `window` (local-time `HH:MM–HH:MM`
label; use it as-is, don't reformat `since`/`ts`, which are UTC), `github.shipped` (merged PRs, each
with `customer_facing`), `github.qa_completed` (marked ready this period), `github.in_flight` (all
your open PRs, each with `isDraft` — a status list, not "changed this period"), `github.reviews_given`
(PRs you reviewed this period, each with a `comments` count), `git.commits`, `sessions`.

## Step 2 — what happened

Only this period. No day totals. Put the most important first:

1. **Merged for customers** — `Shipped: #N <title>`. Any internal (non-customer-facing) merges
   after, one line, marked internal.
2. **Marked ready for review** — from `qa_completed`: `Ready for review: #N <title>`. Real progress.
3. **Your open PRs** — current status of each, not a claim you touched it this period. A draft:
   `#N <title> — still a draft, being tested`; a ready one: `#N <title> — ready, waiting for review`.
4. **Other activity** — short: PRs you reviewed this period (`#N (N comments)`), commits per branch
   (`count > 0`), which worktrees were active (`<worktree>: N turns, active` or `no code changed`).

If nothing was merged and nothing was marked ready, say it in one plain line: `Nothing merged or
marked ready in <window>.` A dozen lines at most. Skip empty sections.

## Step 3 — the one next thing

End with a single clear next action — the most useful thing to do next. Match it to the PR's status.
Never suggest reviewing or merging a draft.

- A ready PR waiting → `#N is ready — ask someone to review it, or merge it if it's approved.`
- A draft you're working on → `You're testing #N. Finish testing it and mark it ready when it passes.`
- A draft untouched for a while → `#N has been a draft for a while. Test it and mark it ready.`
- Several branches touched, none finished → `You worked on 3 branches but didn't finish any. Pick one — #N is closest — and finish it.`
- Time went to internal or refactor work while customer work waits → `This period was internal cleanup. #N is the customer feature that's waiting.`
- A worktree active but no code changed → `#N was active but no code changed — it might be stuck. Unblock it or set it aside.`

If a PR was merged or marked ready, say so in one line and still give the next thing. Don't invent a
problem, but always end with one concrete action.

## Step 4 — notify

One macOS notification: one plain line saying what happened and what to do next. Under ~120 chars,
escape double quotes:

```bash
# merged something:
osascript -e 'display notification "Shipped #4821. Next: #4830 is ready — ask for a review." with title "Productivity check-in" subtitle "<window>"'
# marked a PR ready:
osascript -e 'display notification "Marked #4830 ready for review. Next: get it reviewed." with title "Productivity check-in" subtitle "<window>"'
# nothing finished:
osascript -e 'display notification "Nothing merged. #4830 is a draft — finish testing it and mark it ready." with title "Productivity check-in" subtitle "<window>"'
```

That's the whole tick. End the turn — under `/loop`, the next tick fires on schedule.
