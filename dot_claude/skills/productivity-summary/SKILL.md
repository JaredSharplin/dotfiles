---
name: productivity-summary
description: >
  Periodic work check-in. Runs the collector to snapshot git commits/branch
  movement, GitHub PR and review activity, and Claude session activity across all
  worktrees since the last tick, then prints a tight terminal summary, flags stalled
  work, and fires a macOS notification. Records each snapshot to
  ~/.local/share/productivity/<date>.jsonl for end-of-day reflection. Use when the
  user invokes /productivity-summary, asks "what have I done", or wants a productivity
  check-in. Also arms the recurring schedule when the user asks to "schedule the
  productivity summary", "run it on weekdays", or "automate the check-in" (see Scheduling).
---

# Productivity check-in

A check-in on the last period only — not the whole day. Normally fired on a schedule (see
Scheduling); can also be run by hand anytime. Your job: say plainly what happened, then say the one
next thing worth doing.

**Write like a person talking.** Short, plain sentences. No metaphors, no invented phrases, no
jargon. Do not say "gate", "stage", "pipeline", "momentum", "drive it", "land it", "the finish
line", "motion vs progress", "under your hands", "scatter". Say the plain thing instead: "merge it",
"review it", "finish testing it", "you didn't finish anything". If a sentence needs decoding,
rewrite it.

**Never name a PR by its number alone.** A bare `#56263` tells the developer nothing — they think in
what the PR *does*, not its number. Always lead with a short plain-English handle from the PR's title
(drop the `(feature) |` / `(internal) |`-style prefix and any noise), with the number in parentheses
after: `the reimport-window selector (#56524)`, `the flag removal (#56263)`. This holds everywhere —
the status list, the next action, and the notification. The number is a secondary reference, never
the way you refer to the PR.

**Ask with the question tool, not prose.** If a tick leaves you with a question about an action to
take — offering to apply the `on-hold` label, flip a PR back to draft, chase a named reviewer, or any
change you'd make on the developer's behalf — put it through the AskUserQuestion tool, each option a
concrete action. Never end on a prose "say the word", "let me know if you want…", or a hand-typed
menu. The report itself (Steps 2–4) stays advisory and needs no question; this rule is only for when
you'd otherwise ask in prose. Most ticks have nothing to ask and just end after the notification.

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
your open PRs — a status list, not "changed this period"), `github.reviews_given`
(PRs you reviewed this period, each with a `comments` count), `git.commits`, `sessions`.

Each `github.in_flight` entry carries: `isDraft`; `age_days` (how long the PR has existed);
`idle_days` (days since it last changed); `on_hold` (true when it wears the `on-hold` label — a PR you
deliberately set aside); and `stack_base` (the PR number at the bottom of its git-town stack, or
`null` if it stands alone). `github.stacks` lists each stack as `{base, members}` with `members`
ordered bottom → top. These drive the rules below — don't recompute them yourself.

## Step 2 — what happened

Only this period. No day totals. Put the most important first:

1. **Merged for customers** — `Shipped: #N <title>`. Any internal (non-customer-facing) merges
   after, one line, marked internal.
2. **Marked ready for review** — from `qa_completed`: `Ready for review: #N <title>`. Real progress.
3. **Your open PRs** — current status of each, not a claim you touched it this period. Read the
   in-flight fields instead of treating every PR as an independent line:
   - **On hold** (`on_hold: true`): list once as `<handle> (#N) — on hold`. Never nag about it,
     never count it as waiting on the developer. It's set aside on purpose.
   - **In a stack** (`stack_base` set / see `github.stacks`): show the members together, base first,
     each by its handle. Only the base can move next; the ones above it are `blocked behind <base
     handle> (#<base>)`, not stalled by the developer. Don't give a member its own "waiting" line.
   - **A standalone draft**: `<handle> (#N) — draft, active` when `idle_days` is small; when it's been
     idle a while (say ≥ 2 days), `<handle> (#N) — draft, untouched Nd`.
   - **A standalone ready PR**: `<handle> (#N) — ready, waiting Nd` using `age_days`.
4. **Other activity** — short: PRs you reviewed this period (`#N (N comments)`), commits per branch
   (`count > 0`), which worktrees were active (`<worktree>: N turns, active` or `no code changed`).

If nothing was merged and nothing was marked ready, say it in one plain line: `Nothing merged or
marked ready in <window>.` A dozen lines at most. Skip empty sections.

## Step 3 — the one next thing

End with a single clear next action — the most useful thing to do next. Match it to the PR's status.
Never suggest reviewing or merging a draft. **Never point at an on-hold PR, and never point at a stack
member that isn't the base** — those aren't the developer's move.

- A stack whose **base is ready** → `<base handle> (#<base>) is the base of a stack — merge it to unblock N above.`
- A stack whose **base is a draft** → `<base handle> (#<base>) is the base — finish it; N PRs wait on it.`
- A stack whose **base is on hold** → the whole stack is on hold; say so and look elsewhere for the
  next action. Don't nag any member.
- A standalone ready PR → escalate by age instead of repeating the same line: fresh (`age_days` small)
  → `<handle> (#N) is ready — ask someone to review it, or merge it if it's approved.`; older →
  `<handle> (#N) has been ready Nd — chase a named reviewer or merge it if it's approved.`
- A standalone draft you're working on → `You're testing <handle> (#N). Finish testing it and mark it ready when it passes.`
- A standalone draft untouched a while (`idle_days` ≥ ~2) → `<handle> (#N) has been a draft Nd. Test it and mark it ready.`
- Several branches touched, none finished → `You worked on 3 branches but didn't finish any. Pick one — #N is closest — and finish it.`
- Time went to internal or refactor work while customer work waits → `This period was internal cleanup. #N is the customer feature that's waiting.`
- A worktree active but no code changed → `#N was active but no code changed — it might be stuck. Unblock it or set it aside.`

If every open PR is on hold or blocked behind an on-hold base, there may be nothing to push — say that
plainly rather than inventing a next step. Otherwise always end with one concrete action. If a PR was
merged or marked ready, say so in one line and still give the next thing.

## Step 4 — notify

One macOS notification: one plain line saying what happened and what to do next. Under ~120 chars,
escape double quotes:

Name the PRs here too — a bare number in a notification is useless. Keep each handle short so the
line stays under ~120 chars.

```bash
# merged something:
osascript -e 'display notification "Shipped the CSV export (#4821). Next: the payroll filter (#4830) is ready — ask for a review." with title "Productivity check-in" subtitle "<window>"'
# marked a PR ready:
osascript -e 'display notification "Marked the payroll filter (#4830) ready. Next: get it reviewed." with title "Productivity check-in" subtitle "<window>"'
# nothing finished:
osascript -e 'display notification "Nothing merged. The payroll filter (#4830) is a draft — finish testing it and mark it ready." with title "Productivity check-in" subtitle "<window>"'
```

That's the whole tick. End the turn — the next tick fires on its own schedule (see Scheduling).

## Scheduling

When the user asks to **schedule / automate** this check-in (not run a one-off tick), arm a recurring
cron with the built-in `CronCreate` tool — do not hand-roll a scheduler:

```
CronCreate(cron: "7 9-18 * * 1-5", prompt: "/productivity-summary", recurring: true)
```

That fires the check-in hourly, weekdays only, first tick ~9am and last ~6pm, in local time — so it
auto-starts in the morning and auto-finishes at 6pm. Then call `CronList` to confirm, and tell the
user plainly how far the automation reaches: it fires only while a Claude session is running, it is
**session-only** (dies when the session exits — re-arm when you start a new one), and recurring jobs
**auto-expire after 7 days**. Use `CronDelete` to cancel. (`durable: true` is a real CronCreate
option but a no-op in this environment — it still comes back session-only — so don't bother passing
it.)

(Why not `/loop`: its `ScheduleWakeup` delay caps at 1 hour, so it can't bridge overnight or know
about weekdays — cron is the right built-in for a fixed daily window.)
