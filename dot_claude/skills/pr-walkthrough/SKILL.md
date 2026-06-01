---
name: pr-walkthrough
description: >
  Walk through a complex PR one step at a time, building domain concepts and
  complexity slowly before review. Use when the user invokes /pr-walkthrough
  with a PR number, or asks to "walk me through this PR", "help me understand
  this PR before I review", "explain this PR step by step", or "introduce this
  PR slowly". Comprehension primer, NOT a review — it builds the mental model
  and hands off.
---

# PR Walkthrough

Introduce a complex PR one concept at a time, slowly enough to actually understand it before reviewing. The goal is comprehension, not review: build the mental model, then hand control back.

This skill exists because the natural failure mode is to read the whole diff and then *say* the whole diff — dumping every concept at once under the banner of "step by step." The defense is structural, not a vibe: prep is silent, delivery is one step per turn, and the turn ends after each step. Treat the per-turn gate below as a hard rule, not a preference — the length-default will override "go slow" every time unless it reads as a gate.

## Command Format

```
/pr-walkthrough <pr-number>
```

If no number is given, fall back to the current branch's PR (`gh pr view --json number`). If that fails too, ask which PR — don't guess.

## The two phases

The walkthrough splits into two phases that must not bleed into each other:

- **Prep (private):** read the full PR, ground it against real source, build the ordered step list. Do *all* the comprehension you want here — none of it reaches the user.
- **Delivery (public):** reveal the spine once, then exactly one step per turn.

Naming this split is what stops "I understand it all" from leaking into "I'll output it all." Everything you learn in prep is yours; the user receives it metered, one step at a time.

## Phase 1: Prep (private — produces no user-facing walkthrough content)

Gather everything before you say anything substantive. A brief "Reading PR #1234…" is fine; do not start explaining.

1. **Size it.** `gh pr view <number> --json additions,deletions,title,body`. This gives you the title, description, and scale in one call.
2. **Get the true diff.** Use `gh pr diff <number>` — never `git diff master` in any form (it pulls in stale-master and merge artifacts). Small (<1000 lines): read it whole. Large: `gh pr diff <number> --name-only` first, then read the specific files that matter.
3. **Find the "why."** Read the PR description, and follow any linked issue or Linear ticket. The first delivery step is the problem — you need it grounded in something real, not inferred from the code.
4. **Ground against real source.** This is the one thing the prior session got *right* — keep it. Don't paraphrase the diff:
   - Open the actual files the diff touches and read the surrounding code, not just the changed hunks.
   - Verify constants, enum values, and method signatures by reading them in the repo — cite `file:line` when you reference them in delivery.
   - Never run code to ground a fact. Read it. (Executing against the shared dev DB is forbidden — see global rules. Grep/Read is the tool here.)
5. **Build the ordered step list** using the ordering heuristic below. Each step is one concept that depends only on concepts earlier steps have already established. Keep this list private — it becomes the spine.

If prep reveals the PR is genuinely simple (a few lines, one concept), say so and offer a one-shot explanation instead of a ceremony of steps. The walkthrough is for complexity; don't manufacture it.

## Phase 2: Delivery

### Turn 0 — the spine (its own turn, then stop)

Show the spine: the ordered list of step **titles**, no detail. Then stop and wait for the user to start.

- Titles must be **structural**, not domain jargon. "The core change", "Edge cases it handles", "Who calls into it" — never "the reconciliation ledger's idempotency key". A title may not lean on a concept no earlier step has established. The spine tells the user the *shape* of the journey, not its content.
- The spine is a progress anchor. At the top of each later step, re-anchor: "we've covered the problem and the core change; this step is edge cases." This offloads the "where is this going / how much is left" worry so the user can spend attention on the concept itself.

```
This is a ~5-step walkthrough of PR #1234:

  1. Why this PR exists
  2. The core change
  3. Edge cases it has to handle
  4. Who calls into it
  5. Tests

Ready for step 1?
```

**Showing the spine is the entire turn.** Do not append step 1. Wait for the user.

### Steps 1..N — one step per turn

Each turn delivers exactly one step and ends by handing control back.

```
## Step 2 — The core change
(progress anchor: problem established; this is the central change)

<a few sentences building one concept, at most one short code excerpt with file:line>

Ready for the next, or want to dig into this one?
```

## The per-turn contract (the load-bearing rule)

**Each turn delivers exactly one step and ends by handing control back. Producing step N+1 before the user replies is a failure of the skill, not a convenience.**

This is a gate, not a soft preference. State it that way to yourself every turn. If you have written the next step's content before the user has responded, delete it — you have broken the skill.

## What counts as one step

One step = **one concept that depends only on concepts already established**. A few sentences; at most one short code excerpt.

- If a step needs two code blocks to land, it's two steps.
- If you're tempted to write "and also…", the "also" is the next step.
- A step never forward-references a concept a later step introduces.

## Ordering heuristic (this is what "slowly" means)

Order delivery so complexity only ever builds on what's already established:

1. **The problem / why** — no code. What's broken or missing, why this PR exists.
2. **The core change** — the central abstraction or data-model shift, in its simplest form. The one thing that, understood, makes the rest legible.
3. **Edge cases & refinements** — what the core change has to handle that complicates it.
4. **Call sites / consumers** — who depends on the change and how their behavior shifts.
5. **Tests** — last. They're the most context-dependent; they only make sense once the behavior is established.

Each step may only lean on what earlier steps established. That ordering *is* the slow build.

## Interaction vocabulary

Honor these from the user at any step:

- **next** — deliver the next step.
- **dig in** / a specific question — go deeper on the *current* step. This is the opt-in depth: detail is available on demand, never forced. Answering a dig-in is still one turn — answer, then hand back.
- **skip** — drop the current step's depth, move on.
- **back** — re-summarize the previous step.
- **map** — re-show the spine with a "you are here" marker.

## End state — primer, then hand off

This is a primer, not a guided tour. The core change, edge cases, and call sites *are* the meat — once they're established, the user is oriented enough to review themselves. Do not narrate every file to completion.

After the last step, close by handing control back explicitly:

```
That's the mental model: the problem, the core change, the edge cases it
handles, and who calls into it. You're oriented to review now. Want to start,
or dig into any step first?
```

Do not slide into doing the review yourself. The skill's job ends at comprehension.

## Anti-patterns (the specific failures this skill prevents)

- **Roadmap-then-execute in one message.** Showing the spine is a whole turn. If you show it and then start step 1, you've dumped. Stop after the spine.
- **"Step by step" as a formatting style.** Numbered sections in one long message is not step-by-step — it's a dump with headers. Step-by-step is a *turn-taking contract about pace*, not a layout.
- **Front-loading vocabulary in titles.** A spine that names unmet domain concepts is the dump in miniature. Structural titles only.
- **Paraphrasing the diff instead of grounding it.** Cite real `file:line`, verify real constant values. Comprehension built on a paraphrase is built on sand.
- **Continuing past a handoff.** Once you've handed control back, the turn is over. Wait.
