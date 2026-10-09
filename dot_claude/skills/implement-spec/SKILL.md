---
name: implement-spec
description: Build a spec's slices to draft PRs hands-off with an agent workflow - load when building the slices of a ~/notes/specs/<project>/spec.md, or resuming a stalled build.
---

# Implement spec

Takes an approved `spec.md` (written with `/spec`) and builds its slices to draft PRs with no manual steps between them. This session is the **coordinator**: it plans the run, launches [`build-workflow.js`](build-workflow.js), relays each **stop** to the user, and keeps the spec's Build table current. Agents make every code change, environment fix and PR edit — the script's `RULES` constant is their one source of ground rules.

The coordinator reads state (workflow journals, `gh pr checks`, the spec), launches and resumes workflows, and edits `~/notes`. Anything an agent result leaves to judgement — a declined review finding, a spec decision that looks wrong, a destructive local DB command, a scope change — goes to the user, and the coordinator acts on their answer, updating the spec first when the answer changes it.

## Steps

### 1. Plan the run

Read `spec.md`. Slices run **strictly in sequence**: slice N+1 starts only once slice N has passed the **QA gate** and CI, so every slice builds on a proven-working state. Where each slice branches from is a separate, git-only choice:

- `base: "previous"` — **stack** on the previous slice's branch (git town) when the slices touch the same code.
- `base: "master"` — branch off master when the slice overlaps nothing before it.

Write per-slice `notes`: pointers to the code the slice touches, open nits from earlier reviews, and choices the spec leaves to implementation.

Done when every remaining slice has a base and notes, and the spec's Build section records the order, bases and a slice / branch / PR table.

### 2. Launch

```
Workflow({
  scriptPath: "/Users/jaredsharplin/.claude/skills/implement-spec/build-workflow.js",
  args: {
    spec: "/Users/jaredsharplin/notes/specs/<project>/spec.md",
    slices: [{ slice: 1, base: "master", notes: "..." }, ...],
    resume: null,
    known_issues: []
  }
})
```

To continue a slice that already has a PR, pass `resume: { slice, pr_number, branch, worktree_path, app_url, qa_checklist, start_at: "review" | "qa" | "ci" }` and list only the later slices in `slices`. Carry `known_issues` forward from the previous run's result.

Done when the workflow's completion notification arrives.

### 3. Relay and record

Record each returned slice's branch and PR in the Build table, then commit and push `~/notes` (see `/spec`, "Ending a session"). A slice not `done` is a **stop**: tell the user its stage and blockers in plain terms (table below), get the decision, and relaunch with `resume`.

Done when every slice is `done` — a draft PR with QA screenshots and green CI — or the user holds the one decision that unblocks the next run.

## Stops

| Stage | What it means |
|---|---|
| Preflight | Local dev isn't ready (a failing migration, git town or `gh` setup). The result names the one command for the user. |
| Build / Review | The spec looks wrong for the slice, or a review finding needs a call. |
| QA | The fix agent returned `blocked`, or three QA rounds still failed. |
| CI | A check stayed red after three fix rounds. |

## The QA gate

The gate is a workflow step of agent type `manual-verifier` — workflow agents have no Agent tool, so the script dispatches the verifier, one at a time for the one Chrome. A slice fails QA only on a defect its branch introduced. A console error that appears the same way on comparable pages the branch never touched is **known noise**: a fix agent proves it from the code, the script adds it to `known_issues`, and QA re-runs. Master is green, so known noise is the whole meaning of "not caused by this branch".
