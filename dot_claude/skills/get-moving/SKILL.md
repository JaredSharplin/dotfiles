---
name: get-moving
description: >
  Get started on the next piece of work. Opens the PR garden in the browser (every
  open PR as a plant — drafts wilt the longer they sit untouched, ready PRs flower,
  today's merges are harvested), picks one target PR, and prints a single small
  first step plus a short jump-list for reading its diff. Use when the user invokes
  /get-moving (optionally with a PR number), says "help me get started", "what
  should I start on", or "I'm stuck getting started".
---

# Get moving

The forward-facing twin of `/productivity-summary`: that one says what happened, this one starts the
next thing. The developer's hardest step is the first one — this command makes it trivial.

**Hard rules for everything you print:**

- Never explain what code does. No summaries, no walkthroughs, no paragraphs about the change.
  Output is structural only: locations to read, questions to answer, one action to take.
- Plain language, short sentences. Same voice rules as productivity-summary — no jargon, no
  invented phrases.
- The whole terminal output fits in about a dozen lines.

## Step 1 — open the garden

```bash
~/.claude/skills/get-moving/garden.rb
```

Queries live PR data, writes and opens `~/.local/share/productivity/garden.html`. Don't describe
the garden in the terminal — it speaks for itself.

## Step 2 — triage what's stalled

Before picking, clear the noise: a PR that's stuck for a reason only the developer knows will nag the
hourly `/productivity-summary` forever unless that reason is recorded in GitHub's own state. Fix that
here, so it's explained once instead of every hour.

Read the freshest PR data from the collector rather than re-deriving it. Use the last line of
today's log if present, else run the collector once:

```bash
f=~/.local/share/productivity/$(date +%F).jsonl
[ -s "$f" ] && tail -1 "$f" || ~/.claude/skills/productivity-summary/collect.rb
```

From `github.in_flight`, find PRs that look stalled **with no explanation yet** — a ready PR
(`isDraft: false`) that is not `on_hold` and has a largish `age_days`, or a draft idle a while
(`idle_days` ≥ ~2) that is not `on_hold`. **Skip stack members that aren't the base** (`stack_base`
set and ≠ the PR's own number) — they're legitimately blocked behind their base, not stalled.

For each stalled PR, ask one **AskUserQuestion** — "Why is `<handle> (#N)` stalled?", naming it by a
short plain handle from its title, never the bare number — and apply the action the answer maps to
(use the entry's `repo`). Only act on the option chosen; a "leave it" is a real answer,
not a prompt to do nothing quietly:

- **On hold — waiting on customer feedback / a flag rollout / deprioritised** →
  `gh pr edit <n> --repo <repo> --add-label on-hold`. From the next tick the summary lists it as
  on hold and stops nagging.
- **Not actually ready — needs more work** → `gh pr ready <n> --repo <repo> --undo` (back to draft).
- **Blocked on a specific reviewer** → ask who, then `gh pr edit <n> --repo <repo> --add-reviewer <user>`.
- **Still active, leave it** → no change.

If nothing looks stalled, skip this step silently and go straight to the pick.

## Step 3 — pick one target

- A PR number argument (`/get-moving 56263`) wins — target it as asked.
- Otherwise: the draft with the oldest `updatedAt` (most neglected).
- No drafts? The oldest ready PR that's waiting for review.
- Nothing open? Say so in one line and stop.

**Respect the stack.** If the chosen candidate is in a stack (`stack_base` set), the only member that
can move next is the base — walk down and target `stack_base` instead. If that base is `on_hold`, the
whole stack is on hold; skip it and take the next candidate. Never start someone on a PR that's
blocked behind another.

Candidates come from the collector data read in Step 2 (or this query if you skipped it):

```bash
gh search prs --author=@me --state open --limit 50 --json number,title,url,isDraft,updatedAt,repository
```

State the pick in one line, noting the stack when relevant:
`Starting on #53818 — base of a 5-PR stack; the others wait on it.` or
`Starting on #56263 — <title> (draft, untouched 2d).`

## Step 4 — jump-list (one subagent)

Spawn one `Explore` agent. Give it the PR number and repo (`owner/name` from `repository`), and
this contract verbatim:

> Run `gh pr diff <number> --repo <owner/name>` (use `--name-only` first if the PR is large, then
> read the few files that matter). This is a DRAFT PR — the goal is to build the developer's own
> understanding and confidence in the change, not to review or merge it. Return ONLY, in this order,
> nothing else:
> 1. `START HERE:` one concrete ~2-minute action to begin. For a user-facing change this is a manual
>    browser check — name the screen or flow to open in the running app and the thing to do there
>    (derive the entry point from the routes/controllers/views in the diff). For a non-user-facing
>    change, name the single file where the core behaviour begins and what to find there. NEVER "run
>    a test" — CI does that and it builds no understanding.
> 2. `QUESTIONS:` 3–5 plain-language questions that build understanding of how the change actually
>    works, each anchored to where to start looking with a `file` in backticks. Frame them simply and
>    conceptually — e.g. "How and where does the app discover a POS source after an integration is
>    created? (start in `app/models/pos_integration.rb`)". Plain English, no jargon, no code
>    mechanics in the wording. Questions only — do not answer them.
> Do NOT summarize the PR, describe what the code does, list a file without a question attached to
> it, or add any other prose. If you write a paragraph, you have failed the task.

## Step 5 — save the care card and refresh the garden

Write the subagent's output to `~/.local/share/productivity/jumplists/<number>.json`:

```json
{
  "number": 56263,
  "title": "<PR title>",
  "repo": "owner/name",
  "first_step": "<the START HERE line>",
  "questions": ["How and where does ...? (start in `file`)", "..."],
  "generated_at": "<ISO8601 now>"
}
```

Then re-render the garden without opening a second tab (the page refreshes itself every 30s and
will pick this up, highlighting the plant and showing its care card):

```bash
~/.claude/skills/get-moving/garden.rb --target <number> --no-open
```

## Step 6 — print and stop

Print, in order: the pick line, `START HERE`, `QUESTIONS`. Nothing else — no motivation, no closing
advice. End the turn.
