---
name: implement-spec
description: Build a spec's slices to draft PRs hands-off with an agent workflow - load when building the slices of a ~/notes/specs/<project>/spec.md, or resuming a stalled build.
---

# Implement spec

Takes an approved `spec.md` (written with `/spec`) and builds its slices to draft PRs with no manual steps between them. This session is the **coordinator**: it runs [`slice-workflow.js`](slice-workflow.js) once per slice, relays each **stop** to the user, and keeps the spec's Build table current. Agents make every code change, environment fix and PR edit — the script's `RULES` constant is their one source of ground rules.

The coordinator reads state (workflow results and journals, `gh pr checks`, the spec), launches workflows, and edits `~/notes`. Anything an agent result leaves to judgement — a declined review finding, a spec decision that looks wrong, a destructive local DB command, a scope change — goes to the user, and the coordinator acts on their answer, updating the spec first when the answer changes it. A launched workflow owns its agents until it returns: steer a running slice only by stopping the run and relaunching it with `existing` and `start_at`. A `SendMessage` to one of its agents pulls that agent out of the run and leaves the workflow waiting on it. A parent PR merging mid-run needs no steering — git town moves the branch onto master.

## Steps

### 1. Plan the run

Read `spec.md`. A slice that depends on another (the spec's "Depends on" column, or shared code) launches only once that one returns `done` — reviews clean, QA gate passed — so it builds on a proven-working state. Independent slices run in parallel, one workflow each, in batches of about 5. Run the first slice of a new kind of work alone first: a problem its review finds is then fixed once in the notes, not in every parallel PR. Stacking is only for slices that touch the same code; a shared config line that git merges cleanly is no reason to stack. CI runs in the background (step 3) and doesn't hold the next slice: a parent that goes red is fixed on the parent, and git town carries the fix down. Where each slice branches from is a separate, git-only choice: **stack** on an earlier slice's branch when they touch the same code, otherwise branch off master.

Done when the spec's Build section records the order, each slice's base, and a slice / branch / PR table.

### 2. Run the next slice

```
Workflow({
  scriptPath: "/Users/jaredsharplin/.claude/skills/implement-spec/slice-workflow.js",
  args: {
    spec: "/Users/jaredsharplin/notes/specs/<project>/spec.md",
    slice: 2,
    notes: "code the slice touches, open nits from earlier reviews, choices the spec leaves open",
    parent: { branch: "...", pr_number: 123 },   // the stacked-on slice, or null for master
    existing: null,                               // or { pr_number, branch, worktree_path, app_url, qa_checklist }
    start_at: "build",                            // build | revise | review | qa | ci
    revision: null,                               // with start_at "revise": the user's change, in their words
    known_issues: [],                             // carried forward from the previous result
    qa: true                                      // false when the slice changes nothing user-visible (test-only, tooling)
  }
})
```

A slice that already has a PR passes `existing` and the stage to restart from. When the user changes what an open PR should do, update the spec first, then relaunch it with `start_at: "revise"` and their instruction as `revision`: an agent syncs the branch with its parent, makes the change, rewrites the PR's description and QA boxes, and the slice runs review → QA again. The result carries everything the next launch needs: branch, PR, worktree, checklist and `known_issues`.

Done when the workflow's completion notification arrives.

### 3. Record, then continue or relay

Record the slice's branch and PR in the Build table, then commit and push `~/notes` (see `/spec`, "Ending a session"). Relay the result's `reviews` (each round's findings and what was applied) and `exhale_left` (smells an agent kept, with reasons) to the user. A `done` slice sends the coordinator back to step 2 for the next slice, or the next batch once every slice in this one has returned. Anything else is a **stop**: tell the user its stage and blockers in plain terms (table below), get the decision, and relaunch that slice with `existing` and `start_at`.

After a `done` result, watch CI without blocking: start `gh pr checks <n> --watch --fail-fast` with Bash `run_in_background` — never an agent, a workflow stage or a foreground wait. Holding a run open for CI burns tokens and makes a finished slice look stuck. When the command exits: non-zero means a check is red, so tell the user which one and relaunch the slice with `existing` and `start_at: "ci"`, the fix loop; zero gets one line, "CI green on #<n>".

Done when every slice is `done` — a draft PR with QA screenshots and green CI — or the user holds the one decision that unblocks the next run.

## Stops

| Stage | What it means |
|---|---|
| Preflight | Local dev isn't ready (a failing migration, git town or `gh` setup). The result names the one command for the user. |
| Build / Review | The spec looks wrong for the slice, or a fix agent couldn't apply a review finding. |
| Review declined | A fix agent judged a review finding wrong. The user accepts the decline, or relaunches from `review` with their instruction. Both review rounds — the first, and the final one over commits added after it — stop this way. |
| QA | The fix agent returned `blocked`, or three QA rounds still failed. |
| CI | A check stayed red after three fix rounds. |

## The QA gate

The gate is a workflow step of agent type `manual-verifier` — workflow agents have no Agent tool, so the script dispatches the verifier. A slice fails QA only on a defect its branch introduced. A console error that appears the same way on comparable pages the branch never touched is **known noise**: a fix agent proves it from the code, the script adds it to `known_issues`, and QA re-runs. Master is green, so known noise is the whole meaning of "not caused by this branch".

A slice that changes nothing user-visible — test-only or tooling changes — launches with `qa: false`: it skips native dev prep, the gate and the screenshots, and runs build → review.

## When the Workflow tool is unavailable

The script depends on the Workflow tool's API (`agent()` with `agentType`, `isolation`, `schema`; `args`; `scriptPath`). If a launch fails because that API changed, re-read the `workflow-authoring` skill and update the script to match. If workflows are unavailable altogether, run the same stages as background `Agent` calls, one at a time, reusing the script's prompts: a builder with `isolation: "worktree"`, then the review, then `manual-verifier`, then the CI agent — each launched only after the previous one returns.
