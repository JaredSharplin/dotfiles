---
name: address-review-comments
description: >
  Work through unresolved PR review comments end-to-end — fetch open threads
  via GitHub GraphQL, group related feedback, make code changes, run targeted
  tests, dispatch the manual-verifier subagent when the UI is affected, push
  commits, then reply to each thread (without resolving — the reviewer
  verifies). Use when the user invokes /address-review-comments, asks to
  "address PR comments", "respond to review feedback", "work through the
  review", or names a PR with outstanding comments to resolve.
---

# /address-review-comments

End-to-end workflow for working through reviewer feedback on a PR. Optimised for: doing the actual fixes (not just acknowledging), keeping replies grounded in the change you made, and never resolving threads (the reviewer does that after they verify).

The companion of `/create-pr` (which opens the PR) and `/add-cr-info` (which adds explanatory comments *for* reviewers). This skill handles the *inbound* direction: feedback *from* reviewers.

## Step 1: Locate the PR

If the user named a PR number, use it. Otherwise:

```
gh pr view --json number,title,headRefName,baseRefName,state,url
```

If you're not on a branch with an open PR, ask the user to switch to one or pass the PR number.

## Step 2: Fetch unresolved threads

Use the GraphQL API to get only the threads that are still open. The REST `gh pr view --comments` endpoint doesn't distinguish resolved from unresolved.

```bash
PR=<number>
OWNER=$(gh repo view --json owner --jq .owner.login)
REPO=$(gh repo view --json name --jq .name)

gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first:50) {
              nodes {
                author { login }
                body
                createdAt
                url
              }
            }
          }
        }
      }
    }
  }
' -F owner="$OWNER" -F repo="$REPO" -F pr=$PR \
  --jq '.data.repository.pullRequest.reviewThreads.nodes
    | map(select(.isResolved == false))
    | .[]
    | {threadId: .id, file: .path, line: .line, comments: [.comments.nodes[] | {author: .author.login, body: .body, url: .url}]}'
```

Save the result. You'll need the thread IDs to reply via the `addPullRequestReviewThreadReply` mutation.

## Step 3: Group and triage

Group threads by file and by topic — reviewers often leave several comments on a related issue. Present the grouped list to the user with **three options per group**:

- **Fix** — make the code change the reviewer asked for.
- **Defer** — agree it's worth doing, but not in this PR. Bring the user where it will be tracked and why; they post it.
- **Dispute** — disagree with the suggestion. Bring the user the reasoning; they post it.

Default to **Fix** unless the reviewer's comment is clearly a question, a nit, or you have a substantive reason to push back. Only stop and ask when a group is genuinely ambiguous.

## Step 4: Make the changes

Work through fix-marked groups one at a time. For each:

1. Read the file(s) the reviewer pointed at and the surrounding context.
2. Make the change. Don't expand scope — fix exactly what was raised. Adjacent improvements are out of scope (file a follow-up if you spot something).
3. Run targeted tests on the changed file(s):
   ```
   bin/rails test test/path/to/file_test.rb
   ```
   Always pass `:line` when re-running a specific test. If no test exists for the changed file, run the nearest related test file.
4. If lint/type-check matters for the change (Rubocop, Sorbet), run those scoped to the changed files.
5. **Do not commit yet** — batch related fixes into a single logical commit.

## Step 5: Verify UI changes via manual-verifier

If any fixed group touched UI (views, components, JS, CSS), dispatch the `manual-verifier` subagent before committing:

```
Agent({
  subagent_type: "manual-verifier",
  description: "Verify <change> in the browser",
  prompt: "Base host: https://<worktree>.test. How to get there: <Section → Page → control>. Scenario: <specific scenario the change affects>. Expected: <stated outcome>. Report PASS/FAIL with evidence."
})
```

**Pass the click path, not a deep URL** — the subagent reaches features by clicking, since payaus paths are often Turbo Frames that render as bare fragments when hit directly. You've just read the code, so name the nav path.

The subagent returns PASS / FAIL / PARTIAL / BLOCKED. On anything but PASS, surface the report to the user and stop — don't fix and re-verify automatically.

## Step 6: Commit

One commit per logical group of related fixes. Commit messages should reference the reviewer's concern, not just the line changed. Examples:

- `Address review: extract Payslip#taxable_amount memoization`
- `Fix race in PayRun#finalize per @reviewer comment`
- `Defer: tracked in <link> — clarify with reply`

Don't co-author with Claude (per global CLAUDE.md). Don't amend prior commits — create new ones.

## Step 7: Push

Use git town to push the updated branch:

```
git town sync --push
```

This pushes the branch *and* updates the PR. Wait for it to complete before replying to threads — the SHA you post has to exist on the remote.

## Step 8: Reply to threads

For each fixed thread, reply via the GraphQL mutation. **Do not resolve.** The reviewer resolves after they verify the fix.

```bash
gh api graphql -f query='
  mutation($threadId: ID!, $body: String!) {
    addPullRequestReviewThreadReply(input: {
      pullRequestReviewThreadId: $threadId,
      body: $body
    }) {
      comment { url }
    }
  }
' -F threadId="$THREAD_ID" -F body="Fixed in $SHA"
```

**The reply body is `Fixed in <sha>` and nothing else.** No description of the approach, no pointers to other tests, no offers, no reasoning — the SHA is what the reviewer needs and the diff carries the rest.

For a **deferred** or **disputed** thread there is no such reply: bring the wording to the user and let them post it. Writing prose in their voice is not yours to do.

## Step 9: Report

Summarise to the user:

- N threads addressed (X fixed, Y deferred, Z disputed)
- Commits pushed (SHA + one-line)
- Any failed verifications surfaced for follow-up
- Anything you decided not to do and why

## Rules

- **Never resolve threads.** That's the reviewer's job — resolving prematurely makes it harder for them to track that they actually checked the fix.
- **One commit per logical group, not per thread.** Reviewers reading the diff want to see the net change, not a thread-by-thread audit trail.
- **Don't expand scope.** Address only what was raised. Adjacent cleanup goes in a follow-up.
- **A reply is `Fixed in <sha>` and nothing else.** No approach summary, no context, no offers. Anything beyond the SHA is speaking for the user — for a deferred or disputed thread, hand them the wording instead of posting it.
- **Don't push hooks-skip flags.** Per global CLAUDE.md, `--no-verify` is off the table; let pre-commit hooks run.
- **Don't auto-iterate on verification failures.** If manual-verifier returns FAIL, surface and stop. The user decides whether to retry.

## When to refuse

- The PR doesn't exist or has no open threads → say so, stop.
- The user asks you to resolve threads → refuse and explain why (reviewer's job).
- A reviewer's comment is genuinely ambiguous and you can't tell what they're asking → ask the user before guessing.
