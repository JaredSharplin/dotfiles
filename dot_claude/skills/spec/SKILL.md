---
name: spec
description: Plan a larger piece of work as a spec with build-order slices in ~/notes/specs/<project>/spec.md - load when turning a discussed feature into a spec, when picking up the next slice to implement, or before importing an external source document (a Google Doc pitch, spec, or export) into a spec project.
---

# Spec

A larger piece of work becomes one `spec.md` in `~/notes/specs/<project>/`, ending in **slices**: tracer-bullet vertical slices in build order, each roughly one PR. Adapted from Matt Pocock's `to-spec` and `to-tickets` (`mattpocock/skills`).

Alignment comes first: run payaus's `grill-me` beforehand when what to build is still unclear. This skill synthesises what has already been discussed; it does not interview.

When the source arrives as a whole document (Google Doc, Word export), import it first: [`IMPORTING-SOURCE-DOCS.md`](IMPORTING-SOURCE-DOCS.md).

## Writing the spec

### 1. Explore

Read the conversation, any `source-requirements.md`, and the code the work touches, until you can name every module the change builds or modifies.

### 2. Agree the seams — stop and check in

Sketch the seams the feature will be tested at. Prefer existing seams to new ones, and the highest seam available; the ideal number is one. Present them, end the turn with no tool call, and wait for the user to confirm.

### 3. Draft the slices — stop and check in

Look for prefactoring first — make the change easy, then make the easy change.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, backend, UI, tests)
- A completed slice is demoable or verifiable on its own
- Each slice fits in a single fresh context window
- Prefactoring slices come first

</vertical-slice-rules>

Present the slices as a numbered list in build order, one line each on what it delivers end to end. Ask whether the granularity is right and whether any slice should merge or split. End the turn and iterate until the user approves.

### 4. Write `spec.md`

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

The agreed seams, what makes a good test here (external behaviour, not implementation details), and prior art in the codebase.

## Out of Scope

What this spec deliberately excludes.

## Slices

The approved numbered list, in build order.

</spec-template>

Leave out file paths and code snippets — they go stale fast. The exception is a prototype snippet that encodes a decision more precisely than prose (a state machine, a schema): inline its decision-rich part and note it came from a prototype.

## Picking up a slice

Read `spec.md`, take the next slice without a PR, and plan it — the plan follows CLAUDE.md's TDD rules. A slice that reveals a decision the spec got wrong updates `spec.md` in the same change.

## Ending a session

`~/notes` is a git repo (`JaredSharplin/notes`), and the spec only leaves this machine once pushed. Whenever you've written or changed a file under `~/notes/specs/`, commit and push before handing back — this overrides the usual "push only when asked":

```bash
cd ~/notes
git add specs/<project>
git commit -m "<short message>"
git town sync --push
```

Stage only the project directory. A conflict during the sync is the user's to settle — stop and report it.
