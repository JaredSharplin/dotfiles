---
name: shaping
description: Shape Up shaping and slicing - load when collaboratively shaping a solution with the user (negotiating requirements, sketching shapes, running fit checks), when picking up a slice from ~/notes/shaping/<project>/ to implement, or before importing an external source document (a Google Doc pitch, spec, or export) into a shaping project.
---

# Shaping

## Stop and check in

Shaping is negotiation. Present, then wait — don't write the documents and hand them over.

Three gates. At each, put it in a message, end the turn with no tool call, and wait:

1. **Requirements** — before sketching any shape, before writing any file.
2. **Shape** — before slicing.
3. **Slices** — before writing slice plans.

Statuses you chose and shapes you prefer are proposals, not decisions.

---

## Documents

Shaping produces up to four documents, at descending levels of abstraction. Each is **ground truth** for one thing; the level above is a designed view into it, built so context can be acquired quickly.

| Document | File | Ground truth for | Purpose |
|----------|------|------------------|---------|
| **Frame** | `frame.md` | Source, problem, appetite, no-gos | The "why" — concise, stakeholder-level |
| **Shaping doc** | `shaping.md` | R's, shapes, parts, fit checks | The working document — exploration and iteration happen here |
| **Slices doc** | `slices.md` | Slice definitions | The implementation plan — slice summary table + per-slice prose |
| **Slice plans** | `V1-plan.md`, `V2-plan.md`... | Implementation details | One plan per slice, written when the slice is picked up |

Alongside them: `spike-*.md` (focused technical investigations, referenced from the above), `pr-stack.md` (PR stack mapping, added when work goes into flight), and `source-requirements.md` + `images/` (an imported external source document — see [`IMPORTING-SOURCE-DOCS.md`](IMPORTING-SOURCE-DOCS.md)).

All of it lives at `~/notes/shaping/<project>/`. Frame, shaping doc and slices doc each carry `shaping: true` in YAML frontmatter so tooling can find them.

**Picking up a slice:** read `frame.md`, `slices.md`, and `pr-stack.md` before planning. `shaping.md` is the deep reference — read it when a requirement's intent is unclear. Read the spikes a slice or stack explicitly cites.

### Changes ripple in both directions

The system only works while the levels agree with each other, so a change lands in the same operation as its consequences elsewhere:

- **High → low:** change the shaping doc's parts table, and the slices doc changes with it.
- **Low → high:** a slice plan that reveals a new mechanism, or moves a slice's scope, changes the slices doc and the shaping doc with it.

### Lifecycle

Frame (problem/outcome) → Shaping (explore, detail, fit-check) → Slices (plan implementation).

**Frame** can be written first — it captures the "why" before any solution work begins:

- **Source** — original requests, quotes, or material that prompted the work, verbatim
- **Problem** — what's broken, what pain exists, distilled from the source
- **Outcome** — what success looks like, high-level and not solution-specific

### Capturing source material

Whenever the user hands over raw material during framing — a pasted request or quote, an email or Slack message from a stakeholder, a scenario they were told about — **capture it verbatim** in the Source section at the top of `frame.md`, adding each new one as it arrives:

```markdown
## Source

> I'd like to ask again for your thoughts on a user scenario...
>
> Small reminder: at the moment, if I want to keep my country admin rights
> for Russia and Crimea while having Europe Center as my home center...

---

## Problem
...
```

The source is the ground truth; Problem and Outcome are interpretations of it. Keeping it verbatim preserves context that may matter later and allows revisiting the original request when the distillation missed something.

When the source arrives as a whole document instead, import it: [`IMPORTING-SOURCE-DOCS.md`](IMPORTING-SOURCE-DOCS.md).

---

## Sessions

### Starting

Offer the user both entry points. There's no required order — shaping is iterative, and R and S inform each other throughout:

- **Start from R (Requirements)** — describe the problem, pain points, or constraints. Build up requirements and let shapes emerge.
- **Start from S (Shapes)** — sketch a solution already in mind. Capture it as a shape and extract requirements as you go.

### Resuming a doc that already has a selected shape

1. **Display the fit check for the selected shape only** — R × [selected shape] (e.g. R × F), not all shapes
2. **Summarize what is unsolved** — requirements still Undecided, or where the selected shape has ❌

This gives the user immediate context on where the shaping stands and what needs attention.

### Ending

`~/notes` is a git repo (`JaredSharplin/notes`), and shaping documents only leave this machine once they're pushed. So whenever you've written or changed a file under `~/notes/shaping/`, commit and push it before handing back — here that's part of the work, and it overrides the usual "push only when asked".

```bash
cd ~/notes
git add shaping/<project>
git commit -m "<short message>"
git town sync --push
```

Stage the project directory so only this session's files go in. `git town sync --push` pulls remote edits before pushing, keeping notes written on another machine intact. A conflict during the sync is the user's to settle — stop and report it.

---

## Notation

| Level | Notation | Meaning | Relationship |
|-------|----------|---------|--------------|
| Requirements | R0, R1, R2... | Problem constraints | Members of set R |
| Shapes | A, B, C... | Solution options | Pick one from S |
| Components | C1, C2, C3... | Parts of a shape | Combine within the shape |
| Alternatives | C3-A, C3-B... | Approaches to a component | Pick one per component |
| Sub-parts | E1.1, E1.2... | Parts of a part | Add only once the flat list strains |

**CURRENT** is a reserved shape name for the existing system — the baseline that shows where proposed changes fit.

Keep notation throughout as an audit trail. When finalizing, compose new options by referencing prior components (e.g. "Shape E = C1 + C2 + C3-A").

Start flat (E1, E2, E3...). Introduce hierarchy only when there are too many parts to take in at once, when you're reaching a conclusion and want to show structure, or when grouping related mechanisms aids communication:

| Part | Mechanism |
|------|-----------|
| **E1** | **Swap data source** |
| E1.1 | Modify backend indexer |
| E1.2 | Route letters to new service |
| E1.3 | Route posts to new service |
| **E2** | **Add search input** |
| E2.1 | Add input with debounce |

---

## R: Requirements

A numbered set defining the problem space, negotiated collaboratively — not filled in automatically.

- **R states what's needed, not what's satisfied** — satisfaction is always shown in a fit check (R × S)
- Track status: Core goal, Undecided, Leaning yes/no, Must-have, Nice-to-have, Out
- Requirements extracted from a fit check are made standalone, independent of the shape that revealed them
- **Chunking policy:** never more than 9 top-level requirements. Past 9, group related requirements into chunks with sub-requirements (R3.1, R3.2...) so the top level stays at 9 or fewer. This keeps requirements scannable and forces meaningful grouping.

---

## S: Shapes and their parts

A shape is a solution option: a titled set of parts, each part a mechanism.

### Titles

Short and descriptive, capturing the essence of the approach, shown whenever the shape is shown:

- ✅ "E: Modify CUR in place to follow S-CUR"
- ✅ "C: Two data sources with hybrid pagination"
- ❌ "E: The solution" (too vague)
- ❌ "E: Add search to widget-grid by swapping..." (too long)

### Parts are mechanisms

Parts describe what we BUILD or CHANGE, not intentions or constraints:

- ✅ "Route `childType === 'letter'` to `typesenseService.rawSearch()`" (mechanism)
- ❌ "Types unchanged" (constraint — belongs in R)

**Avoid tautologies between R and S.** R states the need (what outcome); S describes the mechanism (how to achieve it). If you find yourself copying text from R into S, stop — the part should add specificity about *how*:

- ❌ R17: "Admins can bulk request members to sign" + C6.3: "Admin can bulk request members to sign"
- ✅ R17: "Admins can bring existing members into waiver tracking" + C6.3: "Bulk request UI with member filters, creates WaiverRequests in batch"

### Parts are vertical slices

Co-locate data models with the features they support, rather than grouping them into a horizontal layer:

- ❌ **B4: Data model** — Waivers table, WaiverSignatures table, WaiverRequests table
- ✅ **B1: Signing handler** — includes WaiverSignatures table + handler logic
- ✅ **B5: Request tracking** — includes WaiverRequests table + tracking logic

When the same logic appears in several parts, extract it as a standalone part the others reference:

```markdown
| **B1** | **Signing handler** |
| B1.1 | WaiverSignatures table: memberId, waiverId, signedAt |
| B1.2 | Handler: create WaiverSignature + set member.waiverUpToDate = true |
| **B2** | **Self-serve signing** |
| B2 | Self-serve purchase: click to sign inline → calls B1 |
| **B3** | **POS signing via email** |
| B3.1 | POS purchase: send waiver email |
| B3.2 | Passwordless link to sign → calls B1 |
```

### Flagged unknown (⚠️)

A mechanism can be described at a high level without being concretely understood. The **Flag** column tracks this:

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **F1** | Create widget (component, def, register) | |
| **F2** | Magic authentication handler | ⚠️ |

- **Empty** = we know concretely how to build it
- **⚠️** = we've described WHAT but don't yet know HOW

**A flagged part fails the fit check.** ✅ is a claim of knowledge — "we know how this shape satisfies this requirement" — and satisfaction requires a mechanism that concretely delivers it. A flag says we don't have one yet, and you can't claim what you don't know, so it's ❌ until resolved.

This distinguishes "we have a sketch" from "we actually know how to do this". Early shapes (A, B, C) often carry many flags — that's fine for exploration. A selected shape carries none, or explicit spikes to resolve them.

---

## Fit check (decision matrix)

THE fit check is the single table comparing all shapes against all requirements: requirements as rows, shapes as columns. This is how we decide which shape to pursue.

```markdown
## Fit Check

| Req | Requirement | Status | A | B | C |
|-----|-------------|--------|---|---|---|
| R0 | Make items searchable from index page | Core goal | ✅ | ✅ | ✅ |
| R1 | State survives page refresh | Must-have | ✅ | ❌ | ✅ |
| R2 | Back button restores state | Must-have | ❌ | ✅ | ✅ |

**Notes:**
- A fails R2: [brief explanation]
- B fails R1: [brief explanation]
```

**The fit check is binary.** Shape columns hold ✅ or ❌ and nothing else — no third state, no inline commentary, and no ⚠️ (that symbol lives only in the Parts table's Flag column). Explanations go in Notes, kept minimal: just the failures.

Always show the full requirement text — a fit check never abbreviates or summarizes a requirement.

**Comparing alternatives within a component** — same format, scoped to that component:

```markdown
## C3: Component Name

| Req | Requirement | Status | C3-A | C3-B |
|-----|-------------|--------|------|------|
| R1 | State survives page refresh | Must-have | ✅ | ❌ |
| R2 | Back button restores state | Must-have | ✅ | ✅ |
```

**Missing requirements.** If a shape passes every check but still feels wrong, there's a requirement nobody has written down. Articulate the implicit constraint as a new standalone R, then re-run the fit check.

### Macro fit check

A separate tool, used when explicitly requested: high-level work with chunked requirements and early shapes where most mechanisms are still ⚠️. Two columns per shape instead of one:

- **Addressed?** — does some part of the shape speak to this requirement at a high level? ✅ (yes), ⚠️ (partially), ❌ (no)
- **Answered?** — can you trace the concrete how, with the mechanism actually spelled out? ✅ or ❌

```markdown
## Macro Fit Check: R × A

| Req | Requirement | Addressed? | Answered? |
|-----|-------------|:----------:|:---------:|
| R0 | Core goal description | ✅ | ❌ |
| R1 | Guided workflow | ✅ | ❌ |
| R2 | Agent boundary | ⚠️ | ❌ |
```

Top-level requirements only (no sub-requirements), and no notes column — the table stays narrow and scannable. Follow it with a separate **Gaps** table listing the specific missing parts and the sub-requirements they relate to.

---

## Communication

**Show full tables.** When displaying R or any S, show every row: all requirements however many, all shape parts including sub-parts (E1.1, E1.2...), all alternatives in fit checks. The full table is the artifact. Shaping is collaborative negotiation, and the user needs the complete picture to spot missing requirements, notice inconsistencies, make informed decisions and track what's been decided — summaries hide detail and shift control away from them.

**Mark changes with 🟡.** When re-rendering a requirements or shape table after a change, put a 🟡 at the start of every changed or added cell's content, so the user spots what's different instead of diffing the table mentally.

---

## Spikes

A spike is an investigation into how the existing system works and what concrete steps a component needs. Reach for one when mechanics or feasibility are uncertain, and **investigate before proposing** — you may find the system already satisfies the requirement.

Each spike is its own file (`spike-<topic>.md`): a standalone investigation document that can be shared or worked on independently of the shaping doc.

```markdown
## [Component] Spike: [Title]

### Context
Why we need this investigation. What problem we're solving.

### Goal
What we're trying to learn or identify.

### Questions

| # | Question |
|---|----------|
| **X1-Q1** | Specific question about mechanics |
| **X1-Q2** | Another specific question |

### Acceptance
Spike is complete when all questions are answered and we can describe [the understanding we'll have].
```

**Questions ask about mechanics:** "Where is the [X] logic?", "What changes are needed to [achieve Y]?", "How do we [perform Z]?", "Are there constraints that affect [approach]?" Effort estimates ("how long will this take?"), vague questions ("is this hard?") and yes/no questions that reveal no mechanics all belong elsewhere — effort is implicit in the steps themselves.

**Acceptance describes the information we'll hold afterward, never a conclusion or decision:**

- ✅ "...we can describe how users set their language and where non-English titles appear"
- ✅ "...we can describe the steps to implement [component]"
- ❌ "...we can answer whether this is a blocker" (that's a decision, not information)
- ❌ "...we can decide if we should proceed" (the decision comes after the spike)

The spike gathers information; decisions are made afterward, based on it.

---

## Slicing

Shaping moves through two phases: **Shaping** (explore the problem and solution space, select and detail a shape) → **Slicing** (break the selected shape into vertical implementation increments).

The transition happens once a shape is selected, passes its fit check, feels right, and is concrete enough that the implementation order is clear. You can't slice a shape you don't yet understand concretely — resolve the flagged unknowns (spikes) first.

Slicing is prose-based: parts (the high-level mechanisms in the shape) become slices (vertical increments drawn from those parts). **Every slice ends in demo-able UI** — a slice without visible output is a horizontal layer, not a vertical slice.

Outputs:

- **Slices doc** — a slice summary table (columns like #, Slice, Parts, Demo headline, Unblocks), followed by per-slice prose detail: the mechanism, the scope, and the demo it ends in
- **Slice plans** — one implementation plan per slice (`V1-plan.md`, `V2-plan.md`...)

### Breadboarding (optional)

Full breadboarding — formal UI/Non-UI affordance tables and wiring diagrams — is **not part of the default flow**. Shapes go from parts and fit checks straight to prose slices, and the design preview in the shape and slices is usually concrete enough on its own.

Reach for a *focused mini-breadboard* only when wiring is genuinely unclear for a single slice: sketch, inline, the affordances and how they connect for that slice alone, then keep moving.
