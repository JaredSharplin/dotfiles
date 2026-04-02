---
name: preprompt
description: >
  Enhance a prompt with guardrails against known Claude failure modes.
  Use when the user invokes /preprompt followed by their prompt text.
  Takes a raw prompt and outputs an improved version for copy-pasting
  into a fresh Claude instance or re-using earlier in the conversation.
---

# Preprompt

Takes a raw prompt and outputs an enhanced version with guardrails that counteract known Claude failure modes (shallow investigation, blame deflection, lazy solutions, etc.).

## Command Format

```
/preprompt <prompt text>
```

If no prompt text is provided, show this usage and stop.

## Workflow

### Step 1: Read the Failure Modes Catalog

Read `references/failure-modes.md` in this skill directory. This contains the anti-pattern catalog with symptoms, counter-instructions, and concrete examples.

### Step 2: Classify the Prompt

Classify `$ARGUMENTS` into exactly one category (this is internal — do not surface it):

| Category | Signals |
|----------|---------|
| `pr-review` | reviewing a PR, code review, checking changes |
| `feature` | building something new, adding functionality |
| `bug-fix` | fixing a bug, investigating an issue, debugging |
| `refactor` | restructuring code, renaming, reorganizing |
| `general` | anything else — docs, config, exploration, questions |

### Step 3: Compose the Enhanced Prompt

Build the enhanced prompt with these sections in order. Use XML tags for structure — Claude processes these more reliably than markdown headers.

**3a. Role frame** (`<role>`)

1-2 grounded sentences. Not theatrical. Example:

> You are a senior engineer who takes ownership. You investigate before asserting, fix root causes instead of symptoms, and back every claim with evidence you personally verified.

Adapt the role to the category — a reviewer mindset for `pr-review`, a builder mindset for `feature`, an investigator mindset for `bug-fix`.

**3b. Universal principles** (`<principles>`)

Draw from the failure modes catalog. Include counter-instructions for all modes marked `all` categories. Write them as sharp, single-sentence directives. Use conditional language ("when X, do Y") rather than blanket commands ("ALWAYS do X").

Include ~6-8 principles. Each one sentence.

**3c. Category-specific rules** (`<task-rules>`)

Include counter-instructions relevant to the classified category only. Draw from failure modes that list the matching category.

Additionally, include these category-specific rules:

**pr-review:**
- Read the PR description/body completely before examining code
- For each changed file, read surrounding context — not just the diff lines
- Trace the call stack: find callers and callees of changed functions
- Evaluate test quality: are the right scenarios tested? Are edge cases covered? Are assertions exact values or vague checks?
- Identify missing tests — "tests pass" is not "adequately tested"
- If the PR has app changes, check that the test changes adequately cover the new behavior as a spec

**feature:**
- Create a feature branch before writing any code
- Write tests first (TDD) — get them failing before writing implementation
- Read existing code patterns in the area before writing new code
- Do not skip branch creation or linting steps

**bug-fix:**
- Reproduce the bug with a failing test before writing any fix
- Do not hypothesize a root cause without evidence from actual debugging
- Add strategic debug output to verify your understanding before committing to a fix
- The main branch is green — if a test fails, your changes caused it

**refactor:**
- Run existing tests before and after changes
- Verify behavior is preserved, not just that tests pass
- Do not sneak behavior changes into a refactor

**general:**
- No additional task-specific rules (omit the `<task-rules>` section entirely)

**3d. Verification checklist** (`<verification>`)

A checklist of things to verify before finishing. This is more effective than vague instructions to "be thorough." Tailor to the category:

**Universal (always include):**
- [ ] Every claim is backed by evidence (file path, line number, command output)
- [ ] I read all relevant context before acting, not just the immediate surface
- [ ] I investigated my own code/changes first before suggesting external causes
- [ ] I completed all prerequisite steps (branch creation, context reading) before making changes

**pr-review additions:**
- [ ] I read the PR description before reviewing code
- [ ] For each changed file, I read surrounding context
- [ ] I evaluated whether test coverage matches the complexity of the change

**feature additions:**
- [ ] Tests were written and failing before implementation code
- [ ] A feature branch was created before any code changes

**bug-fix additions:**
- [ ] The bug is reproduced by a failing test
- [ ] Root cause hypothesis is supported by debug output, not speculation

### Step 4: Output

Output the enhanced prompt as a **single fenced code block** using triple backticks. This makes it trivially copy-pasteable.

The total guardrails (role + principles + task-rules + verification) should be ~400 words — sharp and directive, not verbose. The receiving Claude instance will respect concise instructions better than walls of text.

**Output nothing else.** No preamble ("Here's your enhanced prompt:"), no commentary after. Just the code block.

### Example Output

For `/preprompt Review PR #1234 for the billing refactor`:

````
```
<role>
You are a senior engineer performing a thorough code review. You investigate before asserting, trace full call stacks, and back every observation with evidence from the code.
</role>

<principles>
- When you claim code behaves a certain way, cite the file and line number.
- If something looks wrong, investigate before asserting — read the implementation, don't guess.
- When reviewing changes, read the surrounding context of each file, not just the diff.
- Choose thorough analysis over quick approval. If understanding requires reading 10 files, read 10 files.
- If you're unsure about a side effect, trace the call stack to verify.
- Never blame a framework or library without checking your own usage first.
</principles>

<task-rules>
- Read the PR description/body completely before examining any code.
- For each changed file, open it and read the surrounding context — not just the changed lines.
- Trace the call stack: find all callers of changed functions and verify they handle the new behavior.
- Evaluate test quality: are the right scenarios tested? Are edge cases covered? Are assertions using exact expected values or vague checks like `.present?`?
- Identify missing tests. "Tests pass" is not the same as "adequately tested."
- Check that test changes adequately cover the app changes as a spec — can you understand the intended behavior from the tests alone?
</task-rules>

<verification>
Before finishing your review, verify:
- [ ] You read the PR description before reviewing code
- [ ] For each changed file, you read surrounding context (not just the diff)
- [ ] You traced the call stack for non-trivial function changes
- [ ] You evaluated whether test coverage matches the complexity of the change
- [ ] Every concern you raised cites specific code (file, line, behavior)
- [ ] You investigated before asserting — no speculation presented as fact
</verification>

<task>
Review PR #1234 for the billing refactor
</task>
```
````
