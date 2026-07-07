---
name: simplify-with-analysis
description: >
  Run the full exhale chain after a feature commit — invoke /simplify first,
  then `bin/diff-quality` (rubycritic + SimpleCov coverage vs master).
  Classify each finding (genuine / false positive / acceptable), apply ONE
  follow-up pass, re-analyse ONCE. This is the canonical "exhale" step
  referenced from the global CLAUDE.md § Design rhythm. Use after a feature
  commit lands and you want a mechanical quality check before moving on, or
  on triggers /simplify-with-analysis, "deep exhale", "run the full simplify
  chain", "do the analysis pass".
---

# /simplify-with-analysis

A deeper exhale than `/simplify` alone — chains the built-in simplification pass with `bin/diff-quality` (rubycritic + diff coverage regression check), with disciplined classification of findings and a strict cap on follow-up iterations.

**Guiding principle: rubycritic findings are *signals*, not a scorecard to chase.** Many smells are false positives on deliberate designs — DSL value objects, declarative config data, cohesive domain classes. Judge every flagged smell against Kent Beck's four rules (see global CLAUDE.md § Design rhythm). When a smell contradicts a design decision already assessed against Beck's rules, the right response is to *extend the ignore config* (`.reek.yml` / `.rubycritic.yml`), not to refactor against your own judgment. Likewise, not every uncovered branch needs a test — trivial getters and defensive fallbacks may be fine. Chasing the score degrades the code.

This skill complements `/refine` (interactive pre-PR branch review) — use `/simplify-with-analysis` after each feature commit as the post-feature exhale, and `/refine` once before opening the PR.

## Step 1: Run /simplify

Invoke the built-in `/simplify` skill via the Skill tool and let it complete its review and any fixes it proposes. Don't skip this step — `/simplify` is the primary signal; rubycritic and coverage are regression guards layered on top.

## Step 2: Run bin/diff-quality

```
bin/diff-quality
```

Runs tests for changed Ruby files with SimpleCov coverage, then RubyCritic comparing the current branch against `master`. The RubyCritic UI incorporates the coverage report.

If tests are already fresh:

```
bin/diff-quality --no-tests
```

If you need a non-master base branch:

```
bin/diff-quality develop
```

After it finishes, read `tmp/rubycritic/report.json` and identify, **for each file changed on this branch**:

- Any file now rated **D or F** that wasn't D/F on master (regression).
- Any new smell *types* introduced.
- Coverage gaps on lines this branch added or meaningfully changed.

## Step 3: Classify each finding

For each rubycritic regression or smell:

- **Genuine** — material complexity, real duplication, or a legitimate smell on code this branch introduced. Refactor.
- **False positive** — flagged on deliberate design that has already been reasoned about against Beck's rules. Extend `.reek.yml` / `.rubycritic.yml` ignores. State *why* in the commit message.
- **Acceptable** — minor smell, low return on the refactor. Note and move on.

For each coverage gap on a changed line:

- **Genuine** — branches, conditionals, domain methods on code this branch added or meaningfully changed. Add a test.
- **Acceptable** — trivial accessors, logging, defensive branches that can't realistically be hit, or view helpers verified manually. Note and move on.
- **Pre-existing** — the uncovered lines weren't introduced by this branch. Don't act.

## Step 4: Report findings

Surface findings as a short list, *not* the raw RubyCritic UI. For each:

- File path : line range
- Smell type / coverage gap
- Classification (Genuine / False positive / Acceptable)
- Proposed action (refactor / add test / extend ignore / no-op)

## Step 5: One follow-up pass

Close the loop on Genuine findings in **one** pass:

- For genuine rubycritic regressions, make the refactor.
- For genuine coverage gaps, add the test.
- For false positives, extend the ignore config.

Commit the follow-up changes **separately** from `/simplify`'s commit — the exhale phases stay distinct per the inhale/exhale rhythm.

## Step 6: Re-run once

```
bin/diff-quality --no-tests
```

(or full `bin/diff-quality` if any of the follow-up changes touched test behaviour)

- If clean, stop.
- If new *genuine* findings appeared that weren't in the first pass, **surface them to the user and stop** — do not iterate further. Repeated rounds of "fix → re-analyse → fix" mean you're chasing the tools, not designing.

## Rules

- No full-repo rubycritic sweep. CI mode only (which `bin/diff-quality` enforces).
- No silencing a smell to make the score go up. Ignores are for design decisions already assessed against Beck's rules, not for convenience.
- No low-value tests just to cover a line. A test that doesn't meaningfully exercise behaviour is noise.
- If `/simplify` already addressed a smell or coverage gap, don't double-count it.
- **At most one follow-up pass + one re-analysis per invocation.** Further work is the user's call.

## What to skip

If `bin/diff-quality` reports "No Ruby files changed against master", short-circuit cleanly — there's nothing to analyse. Don't fabricate work.

If the user invokes this skill mid-feature (before a passing test + commit), say so: this skill is for *after* a feature commit, not as a substitute for `/simplify` during active development.
