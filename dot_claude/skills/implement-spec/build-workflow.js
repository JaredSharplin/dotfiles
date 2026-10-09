export const meta = {
  name: 'implement-spec',
  description: 'Build spec slices to draft PRs one at a time: build, review, browser-QA gate, PR screenshots, CI fix loop',
  whenToUse: 'Launched by the implement-spec skill with args {spec, slices, resume, known_issues}',
  phases: [
    { title: 'Preflight', detail: 'Native dev, local DB and git town ready' },
    { title: 'Build', detail: 'TDD build of the slice to a draft PR' },
    { title: 'Review', detail: 'Independent review and fixes' },
    { title: 'QA', detail: 'manual-verifier gate, fix and re-verify' },
    { title: 'PR', detail: 'Screenshots and QA boxes on the PR' },
    { title: 'CI', detail: 'Watch draft CI and fix failures' },
  ],
}

const SPEC = args.spec
const knownIssues = [...(args.known_issues || [])]

const RULES = `Ground rules: CLAUDE.md applies. Work only in the worktree given, by absolute path (EnterWorktree is unavailable to you). Push only with \`git town sync --push\` (load /git-town first). The PR stays a draft: no gh pr ready, no run-bk label, no GitHub comments, no force-push or amend, no bare git stash. The notes repo belongs to the coordinator. If the spec looks wrong for this slice, return blocked and say what decision is needed.`

const PREP = (ctx) => `Leave native dev ready for browser QA in ${ctx.worktree_path}: \`bin/native/ensure_running.sh\` (once), \`bin/rails db:migrate\` when migrations are pending, \`yarn build\`, then \`bin/native/restart\` (never piped through tail or head).`

const RESULT = {
  type: 'object',
  properties: { status: { type: 'string', enum: ['ok', 'blocked'] }, summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } } },
  required: ['status', 'summary', 'blockers'],
}
const BUILD = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['ok', 'blocked'] },
    branch: { type: 'string' }, worktree_path: { type: 'string' }, app_url: { type: 'string' },
    pr_number: { type: 'number' }, qa_checklist: { type: 'string' },
    summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } },
  },
  required: ['status', 'branch', 'worktree_path', 'summary', 'blockers'],
}
const REVIEW = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' }, line: { type: 'number' },
          severity: { type: 'string', enum: ['must_fix', 'should_fix', 'nit'] },
          summary: { type: 'string' }, evidence: { type: 'string' },
        },
        required: ['file', 'severity', 'summary', 'evidence'],
      },
    },
  },
  required: ['findings'],
}
const QA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['PASS', 'FAIL', 'COULD_NOT_RUN'] },
    pages: { type: 'array', items: { type: 'object', properties: { page: { type: 'string' }, result: { type: 'string' }, observations: { type: 'string' }, screenshot_path: { type: 'string' } }, required: ['page', 'result', 'observations'] } },
    noted_noise: { type: 'array', items: { type: 'string' } },
    problems: { type: 'array', items: { type: 'string' } },
  },
  required: ['verdict', 'pages', 'problems'],
}
const QA_FIX = {
  type: 'object',
  properties: {
    outcome: { type: 'string', enum: ['fixed', 'checklist_wrong', 'not_caused_by_branch', 'blocked'] },
    corrected_checklist: { type: 'string' },
    known_issue: { type: 'string' },
    summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } },
  },
  required: ['outcome', 'summary', 'blockers'],
}
const CI = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['green', 'blocked'] },
    rounds: { type: 'number' }, fixes: { type: 'array', items: { type: 'string' } },
    ui_changed: { type: 'boolean' }, summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } },
  },
  required: ['status', 'rounds', 'fixes', 'ui_changed', 'summary', 'blockers'],
}

function verify(ctx, attempt) {
  const known = knownIssues.length ? `\nKnown noise, already proven not caused by any branch — when seen, record it in noted_noise and keep going:\n- ${knownIssues.join('\n- ')}` : ''
  return agent(`Browser-verify draft PR #${ctx.pr_number} on native dev at ${ctx.app_url} (worktree ${ctx.worktree_path}). Sign in with dev-sign-in-url as \`cafe\`, run from that worktree. Reach every page by clicking through the app's menus.

Checklist:
${ctx.qa_checklist}

Pass rule: FAIL only on a defect this branch introduced — something the checklist expects that is missing or wrong, a broken interaction, or a console error from code the branch changed. A console error that also appears on comparable pages the branch never touched is noise: record it in noted_noise and keep going.${known}

Save one PNG screenshot per checklist page under ${ctx.worktree_path}/tmp/qa-slice-${ctx.slice}/ and return the paths.`, { label: `qa:slice-${ctx.slice}#${attempt}`, phase: 'QA', agentType: 'manual-verifier', schema: QA })
}

async function qaGate(ctx) {
  let qa = null
  for (let attempt = 1; attempt <= 3; attempt++) {
    qa = await verify(ctx, attempt)
    if (qa && qa.verdict === 'PASS') return { ok: true, qa }
    if (!qa || qa.verdict === 'COULD_NOT_RUN') return { ok: false, reason: 'QA could not run', qa }
    const fix = await agent(`Browser QA failed for slice ${ctx.slice} of ${SPEC} (draft PR #${ctx.pr_number}, branch ${ctx.branch}, worktree ${ctx.worktree_path}). QA result:
${JSON.stringify(qa, null, 2)}

Current checklist:
${ctx.qa_checklist}

Find the root cause and return one outcome:
- fixed: the branch caused it. Fix it test-first where the behaviour is testable, run the affected tests (bin/rails test file:line) and lints on changed files, commit, push. ${PREP(ctx)}
- checklist_wrong: the branch is right and the checklist sent QA to the wrong place or expected the wrong thing. Return corrected_checklist in full.
- not_caused_by_branch: the symptom appears the same way on comparable pages the branch never touched. Prove it from the code (read originals with \`git show origin/master:<path>\`; master stays checked out where it is) and return known_issue: one line naming the symptom, the pages, and the cause.
- blocked: none of the above, or it needs a decision.
${RULES}`, { label: `qa-fix:slice-${ctx.slice}#${attempt}`, phase: 'QA', schema: QA_FIX })
    if (!fix || fix.outcome === 'blocked') return { ok: false, reason: 'QA fix blocked', qa, fix }
    if (fix.outcome === 'checklist_wrong' && fix.corrected_checklist) ctx.qa_checklist = fix.corrected_checklist
    if (fix.outcome === 'not_caused_by_branch' && fix.known_issue) knownIssues.push(fix.known_issue)
  }
  return { ok: false, reason: 'QA still failing after 3 rounds', qa }
}

async function review(ctx) {
  const found = await agent(`Review draft PR #${ctx.pr_number}, slice ${ctx.slice} of ${SPEC} (read the slice and the Implementation Decisions). Load the \`code-review\` skill and follow it. Read the diff only through \`gh pr diff ${ctx.pr_number}\`; the code at ${ctx.worktree_path} is context, read-only. Serious issues only: correctness, fidelity to the spec and scope creep, Sorbet strictness, design-system and ViewComponent conventions, test quality, rules in .abide/rubric.json. Evidence for every finding.`, { label: `review:slice-${ctx.slice}`, phase: 'Review', schema: REVIEW })
  const actionable = (found?.findings || []).filter(f => f.severity !== 'nit')
  if (!actionable.length) return { ok: true, summary: 'No actionable findings' }
  const fix = await agent(`Apply review findings to draft PR #${ctx.pr_number} (branch ${ctx.branch}, worktree ${ctx.worktree_path}):
${JSON.stringify(actionable, null, 2)}

Check each against the code and apply the genuine ones (test-first for behaviour). A finding you judge wrong stays unapplied: list it in your summary as declined, with the reason, for the developer to decide. Run affected tests and lints, commit, push. ${PREP(ctx)}
${RULES}`, { label: `review-fix:slice-${ctx.slice}`, phase: 'Review', schema: RESULT })
  return { ok: !!fix && fix.status === 'ok', summary: fix ? fix.summary : 'review fix agent failed', fix }
}

async function publishQa(ctx, qa) {
  return agent(`Update draft PR #${ctx.pr_number}'s body (worktree ${ctx.worktree_path}): use the /git-town skill's screenshot workflow to upload these screenshots into the Screenshots section, and tick only the Manual Browser QA boxes this QA verified. Edit those sections surgically and keep the rest of the body as it is.
${JSON.stringify(qa, null, 2)}
${RULES}`, { label: `pr:slice-${ctx.slice}`, phase: 'PR', schema: RESULT })
}

async function ciLoop(ctx) {
  return agent(`Get draft PR #${ctx.pr_number}'s CI green (branch ${ctx.branch}, worktree ${ctx.worktree_path}). Drafts run the GitHub checks (Abide and others), not Buildkite. Up to 3 rounds: \`gh pr checks ${ctx.pr_number} --watch\`; on a failure read \`gh run view <id> --log-failed\`, fix the cause (for Abide: .claude/ABIDE.md, the rule in .abide/rubric.json, and bin/abide_check.rb locally when feasible), run affected tests and lints, commit, push, watch again. A red check is this branch's to fix forward. Set ui_changed when a fix changes what renders. ${PREP(ctx)}
${RULES}`, { label: `ci:slice-${ctx.slice}`, phase: 'CI', schema: CI })
}

async function build(spec, parent) {
  const base = spec.base === 'previous' && parent
    ? `Stack on ${parent.branch} (PR #${parent.pr_number}). That branch is checked out in another worktree, so: \`git fetch origin\`, \`git checkout -b <branch> origin/${parent.branch}\`, record the parent with \`git town set-parent ${parent.branch}\` (or \`git config git-town-branch.<branch>.parent ${parent.branch}\` if that wants a TTY), and open the PR with \`--base ${parent.branch}\`.`
    : 'Branch off master with `git town hack <branch>`.'
  const result = await agent(`Build SLICE ${spec.slice} of ${SPEC} to a DRAFT PR. Read the whole spec, then load the \`spec\` skill and follow "Picking up a slice". You are in a fresh worktree; return its absolute path as worktree_path and https://<worktree dirname>.test as app_url.
${spec.notes || ''}

${base}

Process: load /git-town. Inhale — load /write-ruby-tests, failing tests first, then the implementation; load /design-system-haml before any HAML; commit. Exhale — /simplify-with-analysis master, cleanups in a separate commit. Lint changed files (rubocop, srb tc, haml-lint) and fix what they report. Run touched test files (bin/rails test file:line) and /flaky-test-check on new tests. Run the local Abide check (bin/abide_model.rb, bin/abide_check.rb) when feasible and fix act findings. Open the draft PR per /git-town (assignee, labels, short human body), leaving screenshots and QA boxes for a later step. ${PREP({ worktree_path: 'your worktree' })}

Return qa_checklist: click-by-click instructions a browser verifier can follow — where to start, what to click, and exactly what must be true on each page, including org settings or feature flags that change what shows and how to turn them on.
${RULES}`, { label: `build:slice-${spec.slice}`, phase: 'Build', isolation: 'worktree', schema: BUILD })
  if (!result || result.status !== 'ok' || !result.pr_number) return { stop: { slice: spec.slice, status: 'blocked', stage: 'Build', result } }
  log(`Slice ${spec.slice}: draft PR #${result.pr_number}`)
  return { ctx: { slice: spec.slice, pr_number: result.pr_number, branch: result.branch, worktree_path: result.worktree_path, app_url: result.app_url, qa_checklist: result.qa_checklist } }
}

async function runSlice(ctx, startAt) {
  const stages = ['review', 'qa', 'ci']
  const from = stages.indexOf(startAt || 'review')
  let reviewSummary = 'skipped'
  if (from <= 0) {
    const rv = await review(ctx)
    if (!rv.ok) return { slice: ctx.slice, pr_number: ctx.pr_number, status: 'blocked', stage: 'Review', rv }
    reviewSummary = rv.summary
  }
  if (from <= 1) {
    const gate = await qaGate(ctx)
    if (!gate.ok) return { slice: ctx.slice, pr_number: ctx.pr_number, status: 'blocked', stage: 'QA', gate }
    await publishQa(ctx, gate.qa)
  }
  const ci = await ciLoop(ctx)
  if (!ci || ci.status !== 'green') return { slice: ctx.slice, pr_number: ctx.pr_number, status: 'blocked', stage: 'CI', ci }
  if (ci.ui_changed) {
    const recheck = await qaGate(ctx)
    if (!recheck.ok) return { slice: ctx.slice, pr_number: ctx.pr_number, status: 'blocked', stage: 'QA after CI fix', recheck }
  }
  return { slice: ctx.slice, pr_number: ctx.pr_number, branch: ctx.branch, worktree_path: ctx.worktree_path, status: 'done', review: reviewSummary, ci: ci.summary }
}

phase('Preflight')
const preflight = await agent(`Preflight for an automated build of ${SPEC} in the payaus repo at /Users/jaredsharplin/programming/tanda/payaus. Confirm, fixing what is safe:
- \`bin/rails db:migrate\` completes against the local native dev DB (fix pending migrations; a failing migration, or anything needing db:reset or db:drop, is blocked — name the exact command for the user);
- \`git config git-town.main-branch\` is set in ~/notes (set it to the branch origin tracks if missing) and in the repo;
- \`gh auth status\` is logged in.
Return blocked with the single action the user must take if any check cannot be fixed safely.`, { label: 'preflight', phase: 'Preflight', schema: RESULT })
if (!preflight || preflight.status !== 'ok') return { status: 'blocked', stage: 'Preflight', preflight, known_issues: knownIssues }

const results = []
let parent = null
if (args.resume) {
  const r = await runSlice({ ...args.resume }, args.resume.start_at)
  results.push(r)
  if (r.status !== 'done') return { results, known_issues: knownIssues }
  parent = r
}
for (const spec of args.slices || []) {
  const built = await build(spec, parent)
  if (built.stop) { results.push(built.stop); break }
  const r = await runSlice(built.ctx, 'review')
  results.push(r)
  if (r.status !== 'done') break
  parent = r
}
return { results, known_issues: knownIssues }
