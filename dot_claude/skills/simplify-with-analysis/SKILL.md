---
name: simplify-with-analysis
description: >
  Run the full exhale chain after a feature commit — gather findings from a
  report-only /code-review pass, a cold Beck-rules subagent, and
  `bin/diff-quality` (rubycritic + SimpleCov coverage vs master) WITHOUT
  touching the code, post ONE consolidated summary of every finding before
  editing anything, then apply in ONE follow-up pass and re-analyse ONCE.
  This is the canonical "exhale" step referenced from the global CLAUDE.md
  § Design rhythm. Use after a feature commit lands and you want a quality
  check before moving on, or on triggers /simplify-with-analysis, "deep
  exhale", "run the full simplify chain", "do the analysis pass".
---

# /simplify-with-analysis

A deeper exhale than `/simplify` alone. It gathers findings from three passes **without touching the code**, surfaces every one of them in a single summary **before any edit**, then applies fixes in one disciplined pass with a strict cap on follow-up iterations.

**Report before edit — this is the point of the skill.** The summary exists so you can *see* the review before the code changes. If ten findings surface and only one gets actioned, that ratio is a signal — noisy reviewers, or under-actioning — and it only reaches the user if all ten are posted before anything is applied. So nothing is edited until Step 2's summary is out. Deciding what to action is still Claude's call; the summary is visibility, not an approval gate.

**Guiding principle: rubycritic findings are *signals*, not a scorecard to chase.** Many smells are false positives on deliberate designs — DSL value objects, declarative config data, cohesive domain classes. Judge every flagged smell against Kent Beck's four rules (see global CLAUDE.md § Design rhythm). When a smell contradicts a design decision already assessed against Beck's rules, the right response is to *extend the ignore config* (`.reek.yml` / `.rubycritic.yml`), not to refactor against your own judgment. Likewise, not every uncovered branch needs a test — trivial getters and defensive fallbacks may be fine. Chasing the score degrades the code.

This skill complements `/refine` (interactive pre-PR branch review) — use `/simplify-with-analysis` after each feature commit as the post-feature exhale, and `/refine` once before opening the PR.

## Step 1: Gather findings (report-only — no edits yet)

Run all three passes. **None may change code** — this stage only collects findings. Keep each pass's output so Step 2 can consolidate them.

1. **Reuse / simplification / efficiency.** Invoke the built-in `/code-review` skill in report mode — do **not** pass `--fix`. It reviews the feature commit's diff and returns findings (reuse, simplification, efficiency, correctness) without editing. (This replaces running `/simplify`, which would apply fixes immediately and defeat report-before-edit.)

2. **Beck rules 2 & 3 (cold reader).** Dispatch **one** subagent (via the Agent tool) to review the feature commit's diff — a reader with no stake in the code just written, since a self-review inherits authorship bias. Prompt it to **find violations, not defend the code**. It returns findings as `file:line — rule — one-line reason`; "no issues" is allowed only after it has checked each tell against specific lines. It has repo read access — tell it to verify each claim (does the schema already name this? does the framework already provide it?), not guess.
   - **Rule 3 — derived state.** Any stored field (ivar, `attribute`, struct field, boolean flag) that's a pure function of state already held → should be a method, not stored.
   - **Rule 3 — reinvented mechanism.** Any hand-rolled mechanism/format/pattern (a coercion, a string built-and-parsed, a composite key, an untyped hash bag, a helper) that the framework or codebase already provides → name the existing construct.
   - **Friction.** Any `T.must`, cast, `Array(...)` wrapper, or edit to a generated file → name the invention it props up; the fix is the cause, not the symptom.
   - **Rule 2 — naming.** Any name that's a bare adjective/vague noun, an abbreviation or synonym for a term the schema already uses, or *false* about what the code does → the domain's word, in full.

3. **Rubycritic + coverage.** Run `bin/diff-quality`:

   ```
   bin/diff-quality              # tests + coverage, then rubycritic vs master
   bin/diff-quality --no-tests   # if tests are already fresh
   bin/diff-quality develop      # non-master base branch
   ```

   Then read `tmp/rubycritic/report.json` and identify, **for each file changed on this branch**: any file now rated **D or F** that wasn't on master (regression); any new smell *types*; coverage gaps on lines this branch added or meaningfully changed.

## Step 2: Post the consolidated summary — before editing anything

**This is the gate. Do not edit until it is posted.** Output ONE list covering every finding from all three passes, led by a tally so the actioned-vs-total ratio is visible:

> **Exhale review — N findings: actioning X, dismissing Y, deferring Z.**

Then, per finding:

- **Source** (code-review / Beck / rubycritic / coverage)
- **`file:line`** and what it is
- **Disposition + one-line reason** — one of:
  - **Action** — will fix in Step 3.
  - **Dismiss** — false positive; say why (e.g. deliberate design already assessed against Beck's rules; for a rubycritic smell, note it'll be handled by extending `.reek.yml` / `.rubycritic.yml`).
  - **Defer** — acceptable / low return / pre-existing (coverage on lines this branch didn't touch); say why.

Show the dismissed and deferred findings too — the ratio is the diagnostic, so nothing is dropped silently. You decide the dispositions; you don't wait for approval to proceed.

## Step 3: Apply — one pass

Only after the summary is posted, apply everything marked **Action**, in a single pass:

- Genuine code / Beck findings → refactor.
- Genuine coverage gaps → add the test.
- False-positive rubycritic smells → extend the ignore config, stating *why* in the commit message.

Commit the cleanup **separately** from the feature commit — the exhale phases stay distinct per the inhale/exhale rhythm.

## Step 4: Re-run once

```
bin/diff-quality --no-tests
```

(or full `bin/diff-quality` if the follow-up touched test behaviour)

- If clean, stop.
- If new *genuine* findings appeared that weren't in the first pass, **surface them to the user and stop** — do not iterate further. Repeated rounds of "fix → re-analyse → fix" mean you're chasing the tools, not designing.

## Rules

- **Report before edit.** Nothing is applied until Step 2's summary is posted. No pass in Step 1 may use a `--fix`/apply mode.
- No full-repo rubycritic sweep. CI mode only (which `bin/diff-quality` enforces).
- No silencing a smell to make the score go up. Ignores are for design decisions already assessed against Beck's rules, not for convenience.
- No low-value tests just to cover a line. A test that doesn't meaningfully exercise behaviour is noise.
- **At most one follow-up pass + one re-analysis per invocation.** Further work is the user's call.

## What to skip

If `bin/diff-quality` reports "No Ruby files changed against master", short-circuit cleanly — there's nothing to analyse. Don't fabricate work.

If the user invokes this skill mid-feature (before a passing test + commit), say so: this skill is for *after* a feature commit, not as a substitute for `/simplify` during active development.
