export const meta = {
  name: 'implement-spec-slice',
  description: 'Take one spec slice to a verified draft PR: build, review, browser-QA gate, PR screenshots, CI fix loop',
  whenToUse: 'Launched by the implement-spec skill, one run per slice',
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
const STAGES = ['build', 'review', 'qa', 'ci']
const startIndex = STAGES.indexOf(args.start_at || 'build')
const knownIssues = [...(args.known_issues || [])]

const RULES = `Ground rules: CLAUDE.md applies. Work only in the worktree given, by absolute path (EnterWorktree is unavailable to you). Push only with \`git town sync --push\` (load /git-town first). The PR stays a draft: no gh pr ready, no run-bk label, no GitHub comments, no force-push or amend, no bare git stash. The notes repo belongs to the coordinator. If the spec looks wrong for this slice, return blocked and say what decision is needed. Exhale every commit: when the exhale hook fires after a non-refactor commit, run the command it names (\`bin/diff-quality --no-browser --no-tests --last-commit\`), apply the cleanups Beck's four rules call for in a separate refactor commit, and list each smell you leave in place, with the reason, in exhale_left.`

const PREP = (worktree) => `Leave native dev ready for browser QA in ${worktree}: \`bin/native/ensure_running.sh\` (once), \`bin/rails db:migrate\` when migrations are pending, \`yarn build\`, then \`bin/native/restart\` (never piped through tail or head).`

const EXHALE_LEFT = { exhale_left: { type: 'array', items: { type: 'string' } } }
const RESULT = {
  type: 'object',
  properties: { status: { type: 'string', enum: ['ok', 'blocked'] }, summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } }, ...EXHALE_LEFT },
  required: ['status', 'summary', 'blockers'],
}
const BUILD = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['ok', 'blocked'] },
    branch: { type: 'string' }, worktree_path: { type: 'string' }, app_url: { type: 'string' },
    pr_number: { type: 'number' }, qa_checklist: { type: 'string' },
    summary: { type: 'string' }, blockers: { type: 'array', items: { type: 'string' } }, ...EXHALE_LEFT,
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
    head_sha: { type: 'string' },
  },
  required: ['findings', 'head_sha'],
}
const REVIEW_FIX = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['ok', 'blocked'] },
    applied: { type: 'array', items: { type: 'string' } },
    declined: { type: 'array', items: { type: 'object', properties: { finding: { type: 'string' }, reason: { type: 'string' } }, required: ['finding', 'reason'] } },
    head_sha: { type: 'string' },
    summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } },
    ...EXHALE_LEFT,
  },
  required: ['status', 'applied', 'declined', 'head_sha', 'summary', 'blockers'],
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
    ...EXHALE_LEFT,
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
    ...EXHALE_LEFT,
  },
  required: ['status', 'rounds', 'fixes', 'ui_changed', 'summary', 'blockers'],
}

const slice = { slice: args.slice, ...(args.existing || {}) }
const exhaleLeft = []
const reviews = []

function track(result) {
  if (result && result.exhale_left) exhaleLeft.push(...result.exhale_left)
  return result
}

function stop(stage, detail) {
  return { status: 'blocked', stage, detail, ...slice, reviews, exhale_left: exhaleLeft, known_issues: knownIssues }
}

function verify(attempt) {
  const known = knownIssues.length ? `\nKnown noise, already proven not caused by any branch — when seen, record it in noted_noise and keep going:\n- ${knownIssues.join('\n- ')}` : ''
  return agent(`Browser-verify draft PR #${slice.pr_number} on native dev at ${slice.app_url} (worktree ${slice.worktree_path}). Sign in with dev-sign-in-url as \`cafe\`, run from that worktree. Reach every page by clicking through the app's menus.

Checklist:
${slice.qa_checklist}

Coverage, on top of the checklist:
- Every Manual Browser QA box in the PR body (\`gh pr view ${slice.pr_number} --json body\`) — check each one and report it as its own page entry, quoting the box text.
- Every ViewComponent the PR adds or changes (\`gh pr diff ${slice.pr_number} --name-only\`, paths under app/view_components/): open its Lookbook previews (the app's /lookbook) and screenshot each preview state.

Pass rule: PASS means every checklist step, every PR QA box and every changed component's previews were checked and held. FAIL on a defect this branch introduced — something the checklist expects that is missing or wrong, a broken interaction, or a console error from code the branch changed — and FAIL on any step you could not check (a feature flag, data or permission missing), naming what was missing so it can be set up. A console error that also appears on comparable pages the branch never touched is noise: record it in noted_noise and keep going.${known}

Save one PNG screenshot per checklist page, PR box and preview state under ${slice.worktree_path}/tmp/qa-slice-${slice.slice}/ and return the paths.`, { label: `qa#${attempt}`, phase: 'QA', agentType: 'manual-verifier', schema: QA })
}

async function qaGate() {
  let qa = null
  for (let attempt = 1; attempt <= 3; attempt++) {
    qa = await verify(attempt)
    if (qa && qa.verdict === 'PASS') return { ok: true, qa }
    if (!qa || qa.verdict === 'COULD_NOT_RUN') return { ok: false, reason: 'QA could not run', qa }
    const fix = track(await agent(`Browser QA failed for slice ${slice.slice} of ${SPEC} (draft PR #${slice.pr_number}, branch ${slice.branch}, worktree ${slice.worktree_path}). QA result:
${JSON.stringify(qa, null, 2)}

Current checklist:
${slice.qa_checklist}

Find the root cause and return one outcome:
- fixed: the branch caused it — fix it test-first where the behaviour is testable, run the affected tests (bin/rails test file:line) and lints on changed files, commit, push. Also fixed: the local QA data or native dev state the checklist relies on was missing, and you restored it in the local native DB. ${PREP(slice.worktree_path)}
- checklist_wrong: the branch is right and the checklist sent QA to the wrong place or expected the wrong thing. Return corrected_checklist in full.
- not_caused_by_branch: the symptom appears the same way on comparable pages the branch never touched. Prove it from the code (read originals with \`git show origin/master:<path>\`) and return known_issue: one line naming the symptom, the pages, and the cause.
- blocked: none of the above, or it needs a decision.
${RULES}`, { label: `qa-fix#${attempt}`, phase: 'QA', schema: QA_FIX }))
    if (!fix || fix.outcome === 'blocked') return { ok: false, reason: 'QA fix blocked', qa, fix }
    if (fix.outcome === 'checklist_wrong' && fix.corrected_checklist) slice.qa_checklist = fix.corrected_checklist
    if (fix.outcome === 'not_caused_by_branch' && fix.known_issue) knownIssues.push(fix.known_issue)
  }
  return { ok: false, reason: 'QA still failing after 3 rounds', qa }
}

phase('Preflight')
const preflight = await agent(`Preflight for building slice ${args.slice} of ${SPEC} in the payaus repo at /Users/jaredsharplin/programming/tanda/payaus. Confirm, fixing what is safe:
- \`bin/rails db:migrate\` completes against the local native dev DB (run pending migrations; a failing migration, or anything needing db:reset or db:drop, is blocked — name the exact command for the user);
- \`git config git-town.main-branch\` is set in ~/notes and in the repo (set it to the branch origin tracks if missing);
- \`gh auth status\` is logged in.
Return blocked with the single action the user must take if any check cannot be fixed safely.`, { label: 'preflight', phase: 'Preflight', schema: RESULT })
if (!preflight || preflight.status !== 'ok') return stop('Preflight', preflight)

if (startIndex <= 0) {
  const base = args.parent
    ? `Stack on ${args.parent.branch} (PR #${args.parent.pr_number}). That branch is checked out in another worktree, so: \`git fetch origin\`, \`git checkout -b <branch> origin/${args.parent.branch}\`, record the parent with \`git town set-parent ${args.parent.branch}\` (or \`git config git-town-branch.<branch>.parent ${args.parent.branch}\` if that wants a TTY), and open the PR with \`--base ${args.parent.branch}\`.`
    : 'Branch off master with `git town hack <branch>`.'
  const built = track(await agent(`Build SLICE ${args.slice} of ${SPEC} to a DRAFT PR. Read the whole spec, then load the \`spec\` skill and follow "Picking up a slice". You are in a fresh worktree; return its absolute path as worktree_path and https://<worktree dirname>.test as app_url.
${args.notes || ''}

${base}

Process: load /git-town. Inhale — load /write-ruby-tests, failing tests first, then the implementation; load /design-system-haml before any HAML; commit. Exhale — /simplify-with-analysis master, cleanups in a separate commit. Lint changed files (rubocop, srb tc, haml-lint) and fix what they report. Run touched test files (bin/rails test file:line) and /flaky-test-check on new tests. Run the local Abide check (bin/abide_model.rb, bin/abide_check.rb) when feasible and fix act findings. Open the draft PR per /git-town (assignee, labels, short human body), leaving screenshots and QA boxes for a later step. ${PREP('your worktree')}

Return qa_checklist: click-by-click instructions a browser verifier can follow — where to start, what to click, and exactly what must be true on each page, including org settings, feature flags or local data that change what shows and how to set them up. Write the PR's Manual Browser QA boxes from the same steps, one box per step, and add a step for each Lookbook preview state of any ViewComponent this slice adds or changes.
${RULES}`, { label: 'build', phase: 'Build', isolation: 'worktree', schema: BUILD }))
  if (!built || built.status !== 'ok' || !built.pr_number) return stop('Build', built)
  Object.assign(slice, { pr_number: built.pr_number, branch: built.branch, worktree_path: built.worktree_path, app_url: built.app_url, qa_checklist: built.qa_checklist })
  log(`Slice ${args.slice}: draft PR #${slice.pr_number}`)
}

async function reviewRound(round, scope) {
  const found = await agent(`Review draft PR #${slice.pr_number}, slice ${slice.slice} of ${SPEC} (read the slice and the Implementation Decisions). Load the \`code-review\` skill and follow it. Review ${scope}; the code at ${slice.worktree_path} is context, read-only. Serious issues only: correctness, fidelity to the spec and scope creep, Sorbet strictness, design-system and ViewComponent conventions, test quality, rules in .abide/rubric.json. Evidence for every finding. Return head_sha as \`git -C ${slice.worktree_path} rev-parse HEAD\`.`, { label: `review-${round}`, phase: 'Review', schema: REVIEW })
  const findings = found?.findings || []
  const actionable = findings.filter(f => f.severity !== 'nit')
  const record = { round, findings, applied: [], declined: [], head_sha: found?.head_sha }
  reviews.push(record)
  if (!actionable.length) return { ok: true, changed: false }
  const fix = track(await agent(`Apply review findings to draft PR #${slice.pr_number} (branch ${slice.branch}, worktree ${slice.worktree_path}):
${JSON.stringify(actionable, null, 2)}

Check each against the code and apply the genuine ones (test-first for behaviour), listing each in applied. A finding you judge wrong stays unapplied: list it in declined with the reason — the developer decides those. Run affected tests and lints, commit, push. Return head_sha as \`git -C ${slice.worktree_path} rev-parse HEAD\` after pushing. ${PREP(slice.worktree_path)}
${RULES}`, { label: `review-fix-${round}`, phase: 'Review', schema: REVIEW_FIX }))
  if (!fix || fix.status !== 'ok') return { ok: false, stage: `Review (${round})`, detail: fix }
  Object.assign(record, { applied: fix.applied, declined: fix.declined, head_sha: fix.head_sha })
  if (fix.declined.length) return { ok: false, stage: `Review declined (${round})`, detail: record }
  return { ok: true, changed: fix.applied.length > 0 }
}

async function ciAndRecheck(round) {
  const ci = track(await agent(`Get draft PR #${slice.pr_number}'s CI green (branch ${slice.branch}, worktree ${slice.worktree_path}). Drafts run the GitHub checks (Abide and others), not Buildkite. Up to 3 rounds: \`gh pr checks ${slice.pr_number} --watch\`; on a failure read \`gh run view <id> --log-failed\`, fix the cause (for Abide: .claude/ABIDE.md, the rule in .abide/rubric.json, and bin/abide_check.rb locally when feasible), run affected tests and lints, commit, push, watch again. A red check is this branch's to fix forward. Set ui_changed when a fix changes what renders. ${PREP(slice.worktree_path)}
${RULES}`, { label: `ci-${round}`, phase: 'CI', schema: CI }))
  if (!ci || ci.status !== 'green') return { ok: false, stage: `CI (${round})`, detail: ci }
  if (ci.ui_changed) {
    const recheck = await qaGate()
    if (!recheck.ok) return { ok: false, stage: `QA after CI fix (${round})`, detail: recheck }
  }
  return { ok: true, ci }
}

if (startIndex <= 1) {
  const first = await reviewRound('first', `the full diff, read only through \`gh pr diff ${slice.pr_number}\``)
  if (!first.ok) return stop(first.stage, first.detail)
}

if (startIndex <= 2) {
  const gate = await qaGate()
  if (!gate.ok) return stop('QA', gate)
  track(await agent(`Update draft PR #${slice.pr_number}'s body (worktree ${slice.worktree_path}): use the /git-town skill's screenshot workflow to upload these screenshots into the Screenshots section — including the Lookbook preview states — and tick each Manual Browser QA box this QA verified (QA passed, so that is every box). Edit those sections surgically and keep the rest of the body as it is.
${JSON.stringify(gate.qa, null, 2)}
${RULES}`, { label: 'pr-screenshots', phase: 'PR', schema: RESULT }))
}

let checks = await ciAndRecheck('first')
if (!checks.ok) return stop(checks.stage, checks.detail)

const reviewedHead = reviews.length ? reviews[reviews.length - 1].head_sha : null
const finalScope = reviewedHead
  ? `only the commits added since the first review: \`git -C ${slice.worktree_path} diff ${reviewedHead}..HEAD\` (empty means nothing to review — return no findings)`
  : `the full diff, read only through \`gh pr diff ${slice.pr_number}\` (no earlier review ran in this run)`
const final = await reviewRound('final', finalScope)
if (!final.ok) return stop(final.stage, final.detail)
if (final.changed) {
  checks = await ciAndRecheck('after final review')
  if (!checks.ok) return stop(checks.stage, checks.detail)
}

return { status: 'done', ...slice, reviews, exhale_left: exhaleLeft, ci: checks.ci.summary, known_issues: knownIssues }
