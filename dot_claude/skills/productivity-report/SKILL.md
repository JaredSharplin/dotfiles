---
name: productivity-report
description: >
  End-of-day reflection over the productivity log written by /productivity-summary.
  Renders a plain-text activity-by-hour view, peak window, day totals (shipped /
  customer-facing, commits, reviews given), and focus split across worktrees. Then
  reviews the day's Claude conversations for the turns where work went wrong —
  interrupts, rejected tool calls, corrections — and drafts fixes for them. Use when
  the user invokes /productivity-report, asks "how did my day go", "when was I most
  productive", "what went wrong today", or wants to reflect on the day's work. Pass a
  date (YYYY-MM-DD) to report on a past day.
---

# Productivity report

Two halves. The first is the day's numbers, already written by the hourly check-in. The second reads
the day's conversations and asks what should change so tomorrow goes better.

Both scripts live under `productivity-summary/`; this skill is the entry point. Pass the date
through to both — default is today.

## Step 1 — the day's numbers

```bash
~/.claude/skills/productivity-summary/report.rb            # today
~/.claude/skills/productivity-summary/report.rb 2026-07-11 # a past day
```

Let its output stand. Add at most a line or two if there's a genuine read of the day ("peak was
mid-morning, quiet after lunch"). If the log doesn't exist, `/productivity-summary` hasn't run today
— say so rather than fabricating a report, and skip to Step 2 anyway (the conversation review reads
transcripts directly and doesn't need the log).

## Step 2 — the day's friction

```bash
~/.claude/skills/productivity-summary/friction.rb          # today
~/.claude/skills/productivity-summary/friction.rb 2026-07-11
```

Prints JSON and records the counts to `~/.local/share/productivity/friction/<date>.json`.

Read `totals` first. Every count is exact except `corrections`, which is a regex over the developer's
own prose and will include false positives — **never state it as fact the way you state interrupts
and rejections.** "Around 50 messages look like corrections" is honest; "you corrected Claude 56
times" is not.

If `totals` is all zeros, say so in one line and stop. No subagents on a quiet day.

The rest of the JSON:

- `clusters` — the top recurring friction, grouped by `kind` + `tool` + `signature` + `skill`, each
  with `pointers` (`{file, uuid}`) into the transcripts and up to three `samples`. This is the work
  list for Step 3.
- `feedback` — the rare cases where the developer typed a reason when rejecting a tool call. Verbatim
  and short. **Highest-signal data in the whole report — always read every one, and always surface
  them, even if a cluster looks bigger.** A typed reason is the developer stating the rule outright.
- `sessions` — the day's sessions ranked by assistant turns, with `file` and `cwd`.
- `skills` / `worktrees` — where the friction landed. Most friction has no skill attached (`null`);
  that's honest, not a bug — most work happens outside a skill. Don't invent an attribution.
- `trend` — the last 7 recorded days. Only mention it when there's a real movement to point at.

## Step 3 — read what actually happened

Dispatch subagents in parallel, **at most 8 total**. They read the transcripts; you never load them
into this conversation.

**Cluster agents — one per cluster, up to 6.** Give each the cluster's `pointers`, `samples`, and
counts. Each agent must:

1. Read the surrounding turns at each pointer in the transcript file (the file is JSONL; find the
   line whose `uuid` matches, then read the turns before and after it).
2. Work out what Claude actually did and why the developer stopped it.
3. Classify it as a **harness gap** (a missing rule, a missing hook, wrong wording in a skill) or a
   **prompting gap** (the ask was ambiguous or under-specified).
4. Return a drafted fix — the exact CLAUDE.md wording, the hook, or the skill edit — naming the file
   it belongs in.

**Session agents — one per top 2 sessions by turns.** Give each the session's `file` and `cwd`. Each
reads the opening prompt and how the session unfolded, and returns what would have got to the same
place faster. This is the prompting half, and it needs the shape of a whole conversation — friction
markers alone can't show it.

## Step 4 — consolidate

**Harness fixes first.** Each one gets: what went wrong, how often, and the drafted fix with the file
it belongs in. These are the deliverable.

**Then the prompting read** — at most three lines, and only what's specific to this day's sessions.

**Then the trend**, if there's prior data and something actually moved.

Two rules, both absolute:

- **Every finding names a file to change.** A finding that can't point at a CLAUDE.md section, a
  hook, or a skill file gets dropped. No "you could be clearer" with nothing attached to it.
- **Write like a person talking.** Same bar as the hourly check-in: short plain sentences, no
  metaphors, no invented phrases. Don't soften a finding and don't editorialise about the developer's
  frustration — the interrupts locate the harness bug, they aren't the subject.

## Step 5 — leave the drafts on the table

End with the drafted rules laid out, each naming the file it belongs in. Don't ask whether to apply
them and don't apply them yourself — the report is advisory, and `/capture-rule` is there when the
developer wants one written. If nothing was drafted, just end.
