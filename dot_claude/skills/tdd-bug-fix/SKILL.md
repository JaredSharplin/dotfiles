---
name: tdd-bug-fix
description: >
  TDD-first bug fix workflow for Linear tickets. Use when user invokes
  /tdd-bug-fix with a ticket number (e.g., ENG-1234). Enforces strict
  evidence-based debugging with two plan-mode approval gates: one for
  test design, one for fix design. Never hypothesizes a root cause before
  evidence from actual debugging. Never fixes without failing tests.
---

# TDD Bug Fix

Evidence-based bug fixing with two plan-mode gates. Every assumption is verified through debugging before any fix is attempted.

## Command Format

```
/tdd-bug-fix <ticket-number>
```

If no ticket number is provided, show usage and stop.

## Workflow Overview

```
PHASE 1: PLAN MODE (read-only investigation)
  Step 1: Fetch ticket, explore codebase, corroborate claims
  Step 2: Verify customer data via dev console (conditional)
  Step 3: Design failing test cases
  Step 4: Design puts debug statements
  → ExitPlanMode → user reviews

PHASE 1: EXECUTION
  Step 5: Write tests + debug puts → run → verify correct failure
  → Commit test files only

PHASE 2: PLAN MODE (evidence-based fix design)
  Step 6: Compile ALL evidence → hypothesize root cause → design fix
  → ExitPlanMode → user reviews

PHASE 2: EXECUTION
  Step 7: Implement fix, verify tests pass
  Step 8: Remove debug puts, run sorbet, commit
  Step 9: Create PR
```

## Phase 1: Plan Mode (Steps 1-4)

Call `EnterPlanMode` immediately after fetching the ticket.

### Step 1: Investigation

1. Fetch ticket: `mcp__linear__linear` with `action: get, id: <ticket>`
2. Read `references/investigation-checklist.md` in this skill directory
3. **Subagent strategy**: If ticket mentions multiple code areas, launch up to 3 Explore subagents in parallel:
   - Agent 1: Investigate code area A mentioned in ticket
   - Agent 2: Investigate code area B mentioned in ticket
   - Agent 3: Investigate existing test coverage for affected areas
   - If narrowly scoped to one area, investigate sequentially — no subagents
4. Corroborate every ticket claim against actual code
5. Check `git log` for recent changes to affected areas
6. **Do NOT hypothesize a root cause yet**

### Step 2: Console Verification (conditional)

Only if ticket contains customer data examples (org IDs, user IDs, record examples):

1. Load `dev-console` skill
2. Query dev DB to verify the data conditions exist
3. Record exact values found — these become test fixture data

### Step 3: Design Failing Tests

1. Load `write-ruby-tests` skill
2. Design test cases that:
   - Reproduce the exact bug scenario described in the ticket
   - Assert EXPECTED (correct) behavior — so they fail against current buggy code
   - Use exact calculated values, not vague assertions
3. List each test with its setup, action, and expected outcome

### Step 4: Design Debug Puts

1. Read `references/debug-patterns.md` in this skill directory
2. Design strategic puts statements for SOURCE CODE files (not tests):
   - Method entry/exit points in the suspected code path
   - Conditional branch decisions
   - Return values and intermediate calculations
   - Query results (`.to_sql`, `.count`)
3. List each puts with its target file, line, and what it reveals

Write plan to plan file, then call `ExitPlanMode`.

**Phase 1 plan file structure (MANDATORY):**

The plan file must end with an `## Execution Instructions` section. This section ensures the plan is self-contained — the user may clear context after approving, so the plan file is the ONLY source of truth for what to do next.

```markdown
## Execution Instructions

This is a Phase 1 plan. After approval, execute ONLY Step 5:

1. Load `write-ruby-tests` skill, then write the test cases designed above
2. Add debug puts to source files using `[DEBUG tdd-bug-fix]` prefix
3. Run tests with `bin/rails test <file>:<line>` — verify they FAIL
4. Verify debug output shows the buggy behavior described in the ticket
5. `git add` test files ONLY (not source files with debug puts), commit:
   `test | Add failing tests for <TICKET>`

**STOP HERE. Do NOT proceed to fix the bug.**
After committing tests, call `EnterPlanMode` for Phase 2 (evidence-based fix design).
Do NOT hypothesize a root cause. Do NOT write any fix code.
```

**Phase 1 plan MUST contain ONLY:**
- Investigation findings (code paths traced, corroborated claims)
- Test case designs (setup, action, expected outcome)
- Debug puts designs (file, line, what it reveals)
- Execution Instructions section (copy the template above, filling in the ticket number)

**Phase 1 plan MUST NOT contain:**
- Root cause hypotheses or analysis
- Fix proposals, code changes, or before/after diffs
- Any content belonging to Step 6 or later

If you catch yourself writing a "Root Cause" or "Fix Design" section, STOP — you are skipping ahead. Delete it and call `ExitPlanMode`.

## Phase 1: Execution (Step 5)

### Step 5: Write Tests, Add Debug Puts, Verify Failure

1. Load `write-ruby-tests` skill, then write the test cases
2. Add debug puts to source files using `[DEBUG tdd-bug-fix]` prefix
3. Run tests: `bin/rails test <file>:<line>`
4. **Verify TWO things:**
   - (a) Tests fail
   - (b) Debug output shows the buggy behavior matching the ticket description
5. **Stop conditions:**
   - Tests PASS unexpectedly → STOP. Bug understanding is wrong. Re-investigate.
   - Tests fail but debug output contradicts expected buggy behavior → STOP. Re-investigate.
6. Once verified: `git add` test files ONLY (not source files with debug puts), commit:
   ```
   test | Add failing tests for <TICKET>
   ```
7. **MANDATORY STOP: Call `EnterPlanMode` immediately after committing.**
   Do NOT proceed to fix the bug. Do NOT hypothesize a root cause.
   Phase 1 is complete. Phase 2 requires a separate plan-mode approval gate.

## Phase 2: Plan Mode (Step 6)

Call `EnterPlanMode`. (This should already have been called at the end of Step 5.)

### Step 6: Evidence-Based Fix Design

#### 6a. Compile Evidence

Compile ALL evidence gathered so far:
- Ticket description and reproduction steps
- Console data (if queried)
- Failing test output
- Debug puts output showing actual buggy values

#### 6b. Hypothesize Root Cause

**NOW hypothesize the root cause**, citing specific evidence for each claim.

#### 6c. Fix Depth Analysis

Before designing the fix, answer these questions explicitly in the plan:

1. **Localized or systemic?** Is the bug in one specific place, or is the same flawed pattern present in multiple places? Search the codebase for similar patterns — don't assume the ticket describes the full scope.

2. **Where does the flaw actually live?** Trace the bug to its deepest origin. If a shared component (base class, permission system, helper module) has the flaw, that's where the fix belongs — not in each consumer. Ask: "If I fix only the reported instance, would the same bug still exist elsewhere?"

3. **Could this happen again?** Could new code written tomorrow hit the same bug? If so, what would prevent it? Consider whether the fix makes the wrong thing hard to do (systemic protection) vs. just fixing today's instance (whack-a-mole).

4. **Fix depth trade-off:** Weigh the options:
   - **Targeted fix** (patch each affected instance): Lower risk, smaller blast radius, but leaves the underlying flaw intact
   - **Systemic fix** (fix the shared component): Higher confidence, prevents recurrence, but broader blast radius requiring more testing
   - State which approach you recommend and why. If systemic, list all code paths affected and how you'll verify them.

#### 6d. Design the Fix

1. Design the fix at the appropriate depth determined by 6c
2. Specify exact files, exact lines, before/after code
3. Identify edge cases the fix must handle
4. If systemic fix: list reports/consumers that will be affected and how behavior changes for each

Write plan to plan file. Call `ExitPlanMode`.

## Phase 2: Execution (Steps 7-9)

### Step 7: Implement Fix and Verify

1. Implement the fix as designed
2. Run previously-failing tests — they must now pass
3. Run the full test file to check for regressions

### Step 8: Clean Up and Commit

1. Remove ALL `[DEBUG tdd-bug-fix]` puts statements from source files
2. Run `srb tc` — load `sorbet` skill if errors arise
3. Commit (pre-commit hooks run rubocop):
   ```
   fix | <TICKET> - <description>
   ```

### Step 9: Create PR

Create PR using `gh pr create`. PR body must reference the Linear ticket and summarize:
- The bug (what was wrong)
- Root cause (why it happened)
- Fix (what changed)
- Test coverage (what tests verify it)

## Guardrails

These rules override normal behavior at all times:

1. **No fixing without failing tests** — Step 7 cannot begin until Step 5 produces verified failing tests
2. **No root cause hypothesis without evidence** — Step 6 cannot hypothesize until Steps 1-5 provide concrete debug output. The Phase 1 plan file must NEVER contain root cause analysis or fix proposals — these belong exclusively in the Phase 2 plan after test failures and debug output are observed
3. **No assumptions about data** — If the ticket references specific data, verify via console in Step 2
4. **Stop on surprise** — If test results contradict expectations, the current understanding is wrong. Do not push forward. Re-investigate.
5. **One hypothesis at a time** — Gather enough evidence to be confident before proposing a fix
6. **Tests that change after Step 5 must be re-verified** — If tests are modified to make them pass, they no longer prove the bug was fixed. They must fail against the original buggy code first.
7. **Phase 1 plan = observations only** — The Phase 1 plan file must contain ONLY investigation findings, test designs, and debug puts designs. If you find yourself writing "Root Cause", "Fix Design", "Fix", or before/after code diffs, you are violating the workflow. Delete it immediately.
