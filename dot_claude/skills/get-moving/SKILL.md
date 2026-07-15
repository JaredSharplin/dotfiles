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

## Step 2 — pick one target

- A PR number argument (`/get-moving 56263`) wins.
- Otherwise: the draft with the oldest `updatedAt` (most neglected).
- No drafts? The oldest ready PR that's waiting for review.
- Nothing open? Say so in one line and stop.

Get the candidates from one query:

```bash
gh search prs --author=@me --state open --limit 50 --json number,title,url,isDraft,updatedAt,repository
```

State the pick in one line: `Starting on #56263 — <title> (draft, untouched 2d).`

## Step 3 — jump-list (one subagent)

Spawn one `Explore` agent. Give it the PR number and repo (`owner/name` from `repository`), and
this contract verbatim:

> Run `gh pr diff <number> --repo <owner/name>` (use `--name-only` first if the PR is large, then
> read the few files that matter). Return ONLY, in this order, nothing else:
> 1. `FIRST STEP:` one imperative action taking ~2 minutes, naming an exact file:line or exact
>    command. Examples of the right shape: "Open `app/models/foo.rb:42` and read `#sync`",
>    "Run `bin/rails test test/models/foo_test.rb:88`". For a draft PR the step should start its
>    testing (e.g. open the screen the change affects); never suggest review or merge for a draft.
> 2. `READ:` an ordered list of 3–7 stops, each `file:line — <label of 5 words or fewer>`, in the
>    order that makes the change easiest to follow.
> 3. `ANSWER WHILE READING:` 2–3 short questions that guide the reading (e.g. "where does X get
>    its value when the list is empty?"). Questions only — do not answer them.
> Do NOT summarize the PR, describe what the code does, or add any other prose. If you write a
> paragraph, you have failed the task.

## Step 4 — save the care card and refresh the garden

Write the subagent's output to `~/.local/share/productivity/jumplists/<number>.json`:

```json
{
  "number": 56263,
  "title": "<PR title>",
  "repo": "owner/name",
  "first_step": "<the FIRST STEP line>",
  "read": ["file:line — label", "..."],
  "answer": ["question", "..."],
  "generated_at": "<ISO8601 now>"
}
```

Then re-render the garden without opening a second tab (the page refreshes itself every 30s and
will pick this up, highlighting the plant and showing its care card):

```bash
~/.claude/skills/get-moving/garden.rb --target <number> --no-open
```

## Step 5 — print and stop

Print, in order: the pick line, `FIRST STEP`, `READ`, `ANSWER WHILE READING`. Nothing else — no
motivation, no closing advice. End the turn.
