---
name: delegate-to-cursor
description: >
  Hand a coding task to the local cursor-agent CLI, in its own worktree, so it
  runs on Cursor's quota instead of Claude's. Use when the user invokes
  /delegate-to-cursor or says "give this to cursor", or for any coding task
  specced well enough to brief in one go.
---

# Delegate to cursor-agent

cursor-agent runs the task end to end: it reads the code, sets up its worktree, builds, tests and opens the PR. Your part is a brief and one command. Every file you read or command you run is Claude usage the handoff exists to save, so pass on what the conversation already holds and leave the discovery to cursor-agent.

## Steps

1. **Write the brief** to `<scratchpad>/cursor-brief.md`, from the user's request and what this conversation already knows:
   - the task and its acceptance criteria, in the user's words
   - any pointers already in hand: files, PRs, specs, error output. Pass them on as they are.
   - setup, in payaus: "Run `bin/manage-worktrees --non-interactive <branch>` from `~/programming/tanda/payaus`, then `git town set-parent master` inside the new worktree under `~/programming/tanda/worktrees/`. Do all the work there."
   - test-first: write the failing test, make it pass, then refactor, with a commit at each green step and very short commit messages
   - `bundle exec rubocop` and `srb tc` pass on changed files
   - the global rules this task touches. Typical ones: fix lints by restructuring, never with disable comments; `# typed: strict` on new app files (`true` for controllers); no code comments; translated user-facing strings; exact assertions in payroll tests.
   - for a PR task: "Read `~/.claude/skills/git-town/SKILL.md` and follow it to open a draft PR, body style included." Never `gh pr ready`, `git push --force` or `git commit --amend`.
   - for a user-visible change: "Do the browser QA yourself on native dev: run `bin/native/ensure_running.sh` in the worktree, sign in with `dev-sign-in-url`, reach the feature by clicking, then add screenshots and tick the QA boxes you verified, as the git-town skill describes."

2. **Run it in the background** with `run_in_background: true`. In payaus:

   ```bash
   cd ~/programming/tanda/payaus && cursor-agent -p --trust --yolo --output-format text \
     --add-dir ~/programming/tanda/worktrees "$(cat <scratchpad>/cursor-brief.md)"
   ```

   In any other repo, run from its root and swap `--add-dir …` for `-w <name>`, and leave the setup line out of the brief. Carry on with other work while it runs.

3. **Report.** When it finishes, give the user the PR link, or the branch and worktree path if there's no PR, plus cursor-agent's own summary. The handoff ends there: cursor-agent's QA and screenshots stand in for the `manual-verifier` pass the global rules ask for, so dispatch nothing after it.
