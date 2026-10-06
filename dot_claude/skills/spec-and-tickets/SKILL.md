---
name: spec-and-tickets
description: Plan a larger piece of work as a spec plus tracer-bullet tickets in ~/notes/specs/<project>/ - load when turning a discussed feature into a spec, when breaking a spec into tickets, when picking up a ticket to implement, or before importing an external source document (a Google Doc pitch, spec, or export) into a spec project.
---

# Spec and tickets

A larger piece of work becomes one **spec** and a set of **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it. Adapted from Matt Pocock's `to-spec` and `to-tickets` (`mattpocock/skills`).

Everything lives in `~/notes/specs/<project>/`:

```
spec.md
tickets/01-<slug>.md
tickets/02-<slug>.md
source-requirements.md + images/   (only after an import)
```

Alignment comes first: run payaus's `grill-me` beforehand when what to build is still unclear. This skill synthesises what has already been discussed; it does not interview.

When the source arrives as a whole document (Google Doc, Word export), import it first: [`IMPORTING-SOURCE-DOCS.md`](IMPORTING-SOURCE-DOCS.md).

## Writing the spec and tickets

### 1. Explore

Read the conversation, any `source-requirements.md`, and the code the work touches, until you can name every module the change builds or modifies.

### 2. Agree the seams — stop and check in

Sketch the seams the feature will be tested at. Prefer existing seams to new ones, and the highest seam available; the ideal number is one. Present them, end the turn with no tool call, and wait for the user to confirm.

### 3. Write `spec.md`

<spec-template>

## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution, from the user's perspective.

## User Stories

A LONG, numbered list covering every aspect of the feature, each in the form:

1. As an <actor>, I want a <feature>, so that <benefit>

## Implementation Decisions

The decisions made: modules built or modified, their interfaces, schema changes, API contracts, specific interactions, architectural choices, technical clarifications from the user.

## Testing Decisions

What makes a good test here (external behaviour, not implementation details), which modules are tested, and prior art in the codebase.

## Out of Scope

What this spec deliberately excludes.

## Further Notes

Anything else.

</spec-template>

### 4. Draft the tickets

Look for prefactoring first — make the change easy, then make the easy change.

<vertical-slice-rules>

- Each ticket cuts a narrow but COMPLETE path through every layer (schema, backend, UI, tests)
- A completed ticket is demoable or verifiable on its own
- Each ticket fits in a single fresh context window
- Prefactoring tickets come first

</vertical-slice-rules>

Give each ticket its **blocking edges**: the tickets that must complete before it can start.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change (rename a column, retype a shared symbol) whose **blast radius** breaks call sites across the codebase at once, so no vertical slice can land green. Sequence it as **expand–contract**: expand (add the new form beside the old), migrate call sites in batches sized by blast radius (each batch its own ticket, blocked by the expand), then contract (delete the old form, blocked by every batch).

### 5. Quiz the user — stop and check in

Present the breakdown as a numbered list — for each ticket its **title**, **blocked by**, and **what it delivers** end to end. Ask whether the granularity is right, whether each blocking edge genuinely gates its ticket, and whether any ticket should merge or split. End the turn and iterate until the user approves.

### 6. Write the tickets

One file per ticket, `tickets/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first):

<ticket-template>

# <NN>: <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective.

**Blocked by:** the numbers and titles of gating tickets, or "None".

**Status:** todo

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</ticket-template>

### Prose rules for both documents

Leave out file paths and code snippets — they go stale fast. The exception is a prototype snippet that encodes a decision more precisely than prose (a state machine, a schema): inline its decision-rich part and note it came from a prototype.

## Picking up a ticket

1. Read `spec.md` and the ticket. The **frontier** is every `todo` ticket whose blockers are all `done`; with no ticket named, take the lowest-numbered one on it.
2. Set its status to `in progress` and plan it — the plan follows CLAUDE.md's TDD rules.
3. When it merges, tick its acceptance criteria and set `done`.

A ticket that reveals a decision the spec got wrong updates `spec.md` in the same change.

## Ending a session

`~/notes` is a git repo (`JaredSharplin/notes`), and these documents only leave this machine once pushed. Whenever you've written or changed a file under `~/notes/specs/`, commit and push before handing back — this overrides the usual "push only when asked":

```bash
cd ~/notes
git add specs/<project>
git commit -m "<short message>"
git town sync --push
```

Stage only the project directory. A conflict during the sync is the user's to settle — stop and report it.
