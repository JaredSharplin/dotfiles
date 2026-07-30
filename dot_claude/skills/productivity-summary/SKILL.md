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
  productivity summary", "run it on weekdays", or "automate the check-in" (see Scheduling). Also
  rebuilds the PR garden page — every open PR as a plant, with a diagram of what it changes and
  comprehension questions on its specimen sheet.
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
what the PR *does*, not its number. Every PR in the record carries a `handle`: its title with the
`[7/7]`, `ENG-4909` and `(feature) |` noise already stripped. Use it, with the number in parentheses
after — `the reimport window selector (#56524)` — in the next action and in the notification. Don't
re-derive a handle of your own; the number is a secondary reference, never the way you name a PR.

What actually counts as work finished:

- **A PR merged for customers** — a merged PR labelled `feature` or `bug`. This is the main thing.
- **A PR whose build went green** — a ready PR now showing `build_state: passing`
  (`github.started_ci` shows the ones that flipped draft→ready this period). For this developer,
  marking a PR ready isn't "done" — it's how they start CI. So the milestone that means the code
  actually holds up is a **green build**, not the draft→ready flip. When a ready PR is green, that's
  real progress worth naming.

Everything else — commits on unfinished work, a ready PR still building or failing CI, reviews you
left on other PRs, internal or refactor merges, Claude session activity — is work in progress, not
finished. Say that plainly, without putting it down.

Two rules about drafts:

- A draft PR is not finished being tested. Its next step is testing, then marking it ready. Never
  tell the developer to get a draft reviewed or merged.
- Marking a PR ready happens after testing, on the developer's explicit request — not something to
  do or suggest from this summary.

The collector does all the data gathering and all the status wording; you read its JSON, build the
page, and choose the one next thing. Don't gather data yourself and don't re-word what it already said.

## Step 1 — collect

```bash
~/.claude/skills/productivity-summary/collect.rb
```

Appends a record to `~/.local/share/productivity/<today>.jsonl` and prints the same record as JSON.
Everything below is about **this period only**. Read the JSON — `window` (local-time `HH:MM–HH:MM`
label; use it as-is, don't reformat `since`/`ts`, which are UTC), `github.shipped` (merged PRs, each
with `customer_facing`), `github.started_ci` (PRs that flipped draft→ready this period — i.e. CI was
started on them, not necessarily that review is wanted), `github.in_flight` (all your open PRs — a
status list, not "changed this period"), `github.reviews_given` (PRs you reviewed this period, each
with a `comments` count), `git.commits`, `sessions`.

Each `github.in_flight` entry carries: `handle` and `status` — the plain-English name and the
already-worded status line (`green, still yours · 2 commits this period (+103/−7)`, `blocked behind
the POS vendor failures (#57257)`, `draft, untouched 4d`). **Both are derived by the collector from
the fields below, so read them rather than wording your own.** The page prints `status` verbatim;
your job is to choose which PR to point at, not to re-describe its state.

The fields `status` is built from, which the next-action rules still need: `isDraft`; `age_days` (working days the PR has existed —
weekday 9–6 only, so an overnight or weekend doesn't inflate it); `idle_days` (working days since it
last changed, same basis — a PR ready since yesterday afternoon reads well under 1, not "a full day");
`on_hold` (true when it wears the `on-hold` label — a PR you
deliberately set aside); `review_state` (`approved` and `changes_requested` mean a colleague really
did review it — `awaiting_review` does **not**: it's branch protection saying a review is required,
true from the moment a PR goes ready and never anything else, so **never speak from it**, use
`settled` below); `build_state` (`passing`, `pending`,
`failing`, or `none` — a ready PR isn't review-ready until this is `passing`; marking ready just
starts CI); `head_branch`; `work_this_period` (`{count, insertions, deletions}` of the commits that
went into this PR's branch during the window, or `null` if none did — this is how you know which PR
the developer actually worked on); `qa_rounds` (see below); and `stack_base` (the PR number at the bottom
of its git-town stack, or `null` if it stands alone). `github.stacks` lists each stack as
`{base, members}` with `members` ordered bottom → top. These drive the rules below — don't recompute
them yourself.

`qa_rounds` counts the ticks where commits landed on a PR that was **already ready with a green
build** — QA turning up real problems after CI passed. This is normal work, not delay: for this
developer a green build means the code compiles and the tests pass, nothing more. One or two rounds
is ordinary. A count that keeps climbing is the one thing worth naming — it means the change isn't
holding up under testing. Never frame these commits as polishing or as sitting too long.

`quiet_days` is working days since the developer last committed to that PR's branch (local commits
count — they commit far more often than they push). `settled` is the field that means a PR is
genuinely done and needs someone else: ready, green, and no commits for half a working day. **A ready
PR that isn't settled is still the developer's own work in progress** — say "green, still yours", never
"waiting on review" and never anything about a reviewer. Marking a PR ready is how this developer
starts CI, so a fresh ready PR means the work is mid-flight, not finished.

## Step 2 — the page

The status of every PR, a diagram of what each one changes, and the questions worth answering about
it all live on one page. You don't narrate any of it — the page carries it. Ask what needs writing:

```bash
~/.claude/skills/productivity-summary/study.rb --stale
```

That prints `{stale: [...], fresh: [...]}`. A stale PR has no diagram yet, or has one describing an
older head commit. **For each stale PR, dispatch one `general-purpose` subagent, all in a single
message so they run concurrently** — a handful on a first run, usually none or one. Reading a PR diff
costs thousands of lines and it has to stay out of this conversation. Give each the brief below.

Then build the page:

```bash
~/.claude/skills/productivity-summary/study.rb
```

It renders every diagram, writes `~/.local/share/productivity/study.html`, and opens it only when
something actually changed. **Print the path it prints, and nothing else.** No status list, no
per-PR lines, no description of the garden — it speaks for itself.

### The brief for each subagent

Read `gh pr view <number> --json title,body,additions,deletions` and then the diff, following the
size rules in the global CLAUDE.md (`--name-only` first when it's large). Write
`~/.local/share/productivity/study/<number>.json`:

```json
{"number": 57310, "title": "...", "url": "...", "repo": "TandaHQ/payaus",
 "head_sha": "<the head_sha from --stale>", "generated_at": "<ISO8601>",
 "diagram": {"type": "graph", "mmd": "graph TD\n    ..."},
 "questions": [{"question": "...", "answer": "...", "evidence": ["app/models/shift.rb:212"]}]}
```

Return only the diagram type and a one-line note. Nothing else comes back.

**The questions are the point of the page.** Two to four. Every one must be answerable *only by
reading the code* — if the diagram or the PR title answers it, it's dead. Ask about consequences:
what breaks, what happens when a precondition is false, what order things happen in, what the change
now silently permits that it didn't before. Every answer cites `file:line` from this PR's own diff, so
the answer can be checked. Banned: naming trivia, "what does this class do", anything restating the
diagram, anything answerable without opening a file.

**The diagram, one per PR, never skipped** — a config-only PR still gets a flowchart of what changed
and what depends on it. Default to `sequenceDiagram`; `stateDiagram-v2` only when a lifecycle really
changes; `graph TD` for structural work; `erDiagram` only for a real schema change. At most 8 nodes,
and nodes are boundaries and domain objects — never one per changed file. Keep node labels short:
a long label inside a `{diamond}` explodes the shape. Mark what the PR changes, so it reads in
context: in flowcharts `classDef changed fill:#b8bb26,stroke:#98971a,color:#1d2021` plus
`class <node> changed`; elsewhere a `* ` prefix on the label.

Two renderer traps, both silent — the page will warn about a dropped label, but avoid them:

- **ER relationships must put the "one" side on the left.** `USER ||--o{ SHIFT : assigned_to` renders;
  `SHIFT }o--|| USER : assigned_to` deletes the relationship, its label *and* the `USER` entity, with
  no error at all.
- Only `graph`/`flowchart`, `stateDiagram-v2`, `sequenceDiagram`, `classDiagram`, `erDiagram` render.
  `gitGraph`, `pie`, `mindmap`, `gantt` and `timeline` fail outright.

## Step 3 — the one next thing

Choose a single next action — the most useful thing to do next. **Don't print it in the terminal.** It
goes in the notification in Step 4, which is the only channel that reaches the developer while their
hands are elsewhere. Match it to the PR's status. Never suggest reviewing or merging a draft. **Never point at an on-hold PR, and never point at a stack
member that isn't the base** — those aren't the developer's move.

**Read `build_state` first, then `settled` — never `awaiting_review`.** Marking a PR ready just starts
CI. `failing` → the build broke; tell the developer to fix it (their move). `pending`/`none` → CI is
still running; say "wait for the build". When `build_state` is `passing`: a real review outcome wins
(`approved` → "merge it"; `changes_requested` → "address the review"); otherwise `settled: false`
means the work is still the developer's and the next step is finishing it, while `settled: true` is
the only state where a reviewer is the answer. Never mention a reviewer while the build is pending or
red, never on an unsettled PR, and only ever say "merge it" on a green, `approved` PR.

- A stack whose **base is ready but its build is `failing`** → `<base handle> (#<base>) is the base and CI is failing — fix the build; N PRs wait on it.`
- A stack whose **base is ready but building (`pending`/`none`)** → `<base handle> (#<base>) is the base and CI is still running — wait for the build; N PRs wait on it.`
- A stack whose **base is green but not `settled`** → `<base handle> (#<base>) is the base and still yours — finish it; N PRs wait on it.` Don't mention review.
- A stack whose **base is green and `settled`** → `<base handle> (#<base>) is the base, green and quiet Nd — get someone on it so the N above can move.` Don't say merge.
- A stack whose **base is green and `approved`** → `<base handle> (#<base>) is approved — merge it to unblock N above.`
- A stack whose **base is green with `changes_requested`** → `<base handle> (#<base>) has changes requested — address them; N PRs wait on it.`
- A stack whose **base is a draft** → `<base handle> (#<base>) is the base — finish it; N PRs wait on it.`
- A stack whose **base is on hold** → the whole stack is on hold; say so and look elsewhere for the
  next action. Don't nag any member.
- A standalone ready PR → branch on `build_state` first: `failing` → `<handle> (#N)'s build is failing — fix it.`;
  `pending`/`none` → `<handle> (#N) is building — wait for CI.`; then when `passing`:
  `approved` → `<handle> (#N) is approved — merge it.`; `changes_requested` → `<handle> (#N) has changes
  requested — address the review.`; `settled: false` → `<handle> (#N) is green and still yours — finish
  it.`; `settled: true` → `<handle> (#N) has been green and quiet Nd — get someone to review it.`
- A standalone draft you're working on → `You're testing <handle> (#N). Finish testing it and mark it ready when it passes.`
- A standalone draft untouched a while (`idle_days` ≥ ~2) → `<handle> (#N) has been a draft Nd. Test it and mark it ready.`
- **A PR on its third-or-later round of fixes since green** (`qa_rounds >= 3`) → this outranks the
  review-state rules above, because the code isn't done: `<handle> (#N) is on its Nth round of fixes
  since CI went green — the change may be bigger than the PR.` Say that and stop. Don't tell the
  developer to split it or push on; that call needs context this check-in doesn't have.
- Several branches touched, none finished → `You worked on 3 branches but didn't finish any. Pick one — #N is closest — and finish it.`
- Time went to internal or refactor work while customer work waits → `This period was internal cleanup. #N is the customer feature that's waiting.`
- A worktree active but no code changed → `#N was active but no code changed — it might be stuck. Unblock it or set it aside.`

If every open PR is on hold or blocked behind an on-hold base, there may be nothing to push — say that
plainly rather than inventing a next step. Otherwise always land on one concrete action. A PR merged or
marked ready this period is the "what happened" half of the notification, and the action is still the
other half.

## Step 4 — notify

One macOS notification: one plain line saying what happened and what to do next. Under ~120 chars,
escape double quotes:

Name the PRs here too — a bare number in a notification is useless. Keep each handle short so the
line stays under ~120 chars.

The next action here is whatever Step 3 chose — never a different one. In particular, a PR that just
went ready means CI started: never write "ask for a review" or "get it reviewed" unless Step 3 landed
on `settled: true`.

```bash
# merged something:
osascript -e 'display notification "Shipped the CSV export (#4821). Next: the payroll filter (#4830) is green and still yours — finish it." with title "Productivity check-in" subtitle "<window>"'
# started CI on a PR:
osascript -e 'display notification "Started CI on the payroll filter (#4830). Next: wait for the build." with title "Productivity check-in" subtitle "<window>"'
# green and quiet, genuinely needs someone else:
osascript -e 'display notification "The payroll filter (#4830) has been green and quiet 2d. Next: get someone to review it." with title "Productivity check-in" subtitle "<window>"'
# nothing finished:
osascript -e 'display notification "Nothing merged. The payroll filter (#4830) is a draft — finish testing it and mark it ready." with title "Productivity check-in" subtitle "<window>"'
```

That's the whole tick: the page path in the terminal, everything else on the page, one notification.
End the turn — the next tick fires on its own schedule (see Scheduling).

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
