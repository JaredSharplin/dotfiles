# Testing

**ONLY use `bin/rails test file.rb:123`** - ALWAYS use line numbers

⛔ NEVER use `bin/dev test`

## Rules (MANDATORY - verify before writing ANY test)
- [ ] DETERMINISTIC - no if/else or conditional logic
- [ ] EXACT VALUES - calculate expected values first, no `.positive?` or vague checks
- [ ] `assert_in_delta expected, actual` - defaults only, no extra arguments
- [ ] No comments or messages in tests
- [ ] NEVER SKIP - if environment issues block testing, fix them first
- [ ] NEVER "SIMPLIFY" TESTS TO MAKE THEM PASS - if a test fails, fix the code or fix the test logic, don't weaken assertions
- [ ] EXCELLENT COVERAGE IS MANDATORY - tests must thoroughly cover the functionality, not just pass

```ruby
# WRONG
assert result > 0
if condition; assert_equal x, y; else; assert_nil z; end

# RIGHT
hours = 5.0
rate = 25.10
expected = hours * rate  # 125.50
assert_in_delta expected, result
```

# Code Quality

## Linting Commands
- Run `bundle exec rubocop` for Ruby linting
- Run `srb tc` for Sorbet type checking
- If either fails due to missing gems, run `bundle install` first

## ⛔ NEVER DISABLE LINTS - EVER

**This is an ABSOLUTE rule with NO exceptions:**
- ❌ NEVER add `# rubocop:disable` comments
- ❌ NEVER add `# T.unsafe` to bypass Sorbet
- ❌ NEVER add `# typed: ignore` or weaken type strictness
- ❌ NEVER add inline disable comments for ANY linter

**If a linter complains, FIX THE CODE.** Restructure until both rubocop and Sorbet are satisfied. Disabling lints is lazy, creates technical debt, and hides real issues.

## Other Rules
- All code MUST be translated, do not embed plain English into user-facing strings

## Use Enumerable, Not C-Style Loops

⛔ **NEVER** initialize variables, loop with `each`, and mutate. This screams LLM-generated Ruby.

```ruby
# WRONG                                    # RIGHT
total = 0                                  total = items.sum(&:price)
items.each { |i| total += i.price }

names = []                                 names = users.filter_map { |u| u.name if u.active? }
users.each { |u| names << u.name if u.active? }

lookup = {}                                lookup = records.index_by(&:id)
records.each { |r| lookup[r.id] = r }
```

**Chain methods fluently:**
```ruby
users
  .select(&:active?)
  .reject(&:admin?)
  .map(&:email)
  .uniq
```

**Use `.then` for transformations and `.tap` for side effects:**
```ruby
# .then (also known as yield_self) - transform and return new value
User.find(id)
  .then { |user| UserPresenter.new(user) }
  .then { |presenter| presenter.as_json }

# .tap - do something with value, return original
User.new(params)
  .tap { |u| u.role = :member }
  .tap { |u| logger.info("Created: #{u.email}") }
  .save!
```

**Key methods:** `map`, `select`, `find`, `sum`, `group_by`, `index_by`, `filter_map`, `flat_map`, `then`, `tap`

## Use Ruby 3.4 `it` in Single-Parameter Blocks

**Prefer `it`** over named block parameters in short, single-parameter blocks. Still use `&:method` for bare method calls, and named parameters for multi-arg blocks.

```ruby
# &:method for bare calls       # `it` when there's more to the expression
users.map(&:name)               users.map { it.name.downcase }
items.select(&:active?)         items.select { it.score > threshold }
                                prices.sum { it * tax_rate }
```

## Use Ruby 3 Pattern Matching

**Prefer `case/in`** over chains of `if`/`elsif` when destructuring hashes or arrays. Patterns match hash keys partially by default.

```ruby
# Hash destructuring
case response
in {status: 200, body:}  then process(body)
in {status: 404}         then not_found
in {status: 500, error:} then log_error(error)
end

# Array matching with find patterns
case items
in [*, {type: "error", message:}, *] then handle_error(message)
end

# Guard clauses
case user
in {role: "admin", active: true}            then grant_full_access
in {role:, score:} if score >= threshold    then grant_limited_access
end

# Single-pattern extraction with =>
config.dig(:database, :primary) => {host:, port:}
```

# Forbidden Commands

The following commands are PERMANENTLY BANNED and must NEVER be used under ANY circumstances:
- ❌ `bin/dev` (EXCEPT `bin/dev console` for READ-ONLY queries - invoke /dev-console skill first) - FORBIDDEN
- ❌ `rails runner` / `bin/rails runner` - FORBIDDEN
- ❌ `rails console` / `bin/rails console` / `rails c` / `bin/rails c` - FORBIDDEN
- ❌ `ruby -i` / `ruby -pe` / `ruby -ne` for inline file modifications - FORBIDDEN
- ❌ `sed -i` for inline file modifications - FORBIDDEN
- ❌ `awk -i` for inline file modifications - FORBIDDEN
- ❌ `perl -i` / `perl -pe` for inline file modifications - FORBIDDEN
- ❌ `git push` (use `git town sync` instead) - FORBIDDEN
- ❌ `git commit --amend` - FORBIDDEN, always create a new commit instead
- ❌ `git push --force` / `git push -f` / `git push --force-with-lease` - FORBIDDEN
- ❌ `rm` - FORBIDDEN, use `trash` instead for safe deletion

**Why these are banned:**
- They bypass proper testing infrastructure
- They can corrupt development environment
- They skip necessary setup and validation
- Console/runner commands are not reproducible or testable
- Inline file modification scripts (ruby -i, sed -i, etc.) often introduce syntax errors and break files
- These scripts are difficult to debug and impossible to undo without git

**What to do instead:**
1. Run the actual test suite: `bin/rails test path/to/test.rb`
2. Read existing tests to understand behavior
3. Check fixtures and test data
4. Trace through code logic using Read tool
5. If you need to verify something works, write a test for it
6. **For file modifications:** ALWAYS use the Read and Edit tools - NEVER use sed, awk, ruby -i, or perl scripts
7. If you need to edit multiple similar lines, use multiple Edit tool calls or ask the user to do it manually
8. **For pushing changes:** ALWAYS use `git town sync` - NEVER use `git push` directly

**Before executing ANY bash command, ask yourself:**
- Does this command appear in the FORBIDDEN list above?
- If YES → STOP IMMEDIATELY and find an alternative approach

# Modifying Config Files

**MANDATORY rules for ANY config file modification (gitignore, dotfiles, rc files, etc.):**

1. **Investigate existing setup FIRST** - Check what's already configured before making changes
   - Run `git config --global core.excludesfile` to see current gitignore
   - Check for existing dotfiles: `ls -la ~/.*`
   - The solution may already exist

2. **NEVER use `echo >>` to append to files** - This blindly adds content without seeing what's there

3. **NEVER use Write tool on existing files** - Write OVERWRITES the entire file, destroying existing content

4. **ALWAYS use Read then Edit** - Read the file first, then use Edit to make targeted changes

5. **For global gitignore specifically:**
   - Check `git config --global core.excludesfile` first
   - User's global gitignore is at `~/.global_gitignore`

# Git Workflow

Use git town for branch management. Invoke /git-town skill for detailed stacking guidance.
- `git town hack feature/name` to start branches
- `git town sync` instead of `git push`
- Never push directly to master

## Git Town Behavior
When running `git town sync`, it will sometimes edit **unrelated PRs** to update the branch stack metadata shown in PR bodies (`<!-- branch-stack-start -->` / `<!-- branch-stack-end -->`). This is normal behavior to keep stack navigation links correct across all PRs in the stack. Do not treat this as an error or attempt to "fix" it.

## ⛔ NEVER SWITCH BRANCHES TO "CHECK IF TESTS PASS ON MASTER"
**TESTS ALWAYS PASS ON MASTER.** This is a CI guarantee. If a test is failing on your branch:
1. Your branch broke it - analyze YOUR changes to find the cause
2. Use `git diff master -- <file>` to see what YOU changed
3. NEVER run `git checkout master` or `git stash` to "verify" - it wastes time and leaves the repo in a bad state
4. If a test fails, the bug is in YOUR code changes, not master

# GitHub PRs

## ⛔ Analyzing PR Changes
**ALWAYS use `gh pr diff <number>` - NEVER use `git diff master` or `git diff origin/master`**

Why: `git diff` against master includes merge commit artifacts and shows incorrect file lists. Only `gh pr diff` shows the true PR diff that reviewers see.

## Commands
1. First check PR size: `gh pr view <number> --json additions,deletions`
2. If small (<1000 lines): `gh pr diff <number>` (no flags)
3. If large: `gh pr diff <number> --name-only` first, then read specific files
- Do NOT use `--patch` - it shows individual commit patches, not the net PR diff

## ⚠️ Editing PR Bodies
**NEVER replace a PR body wholesale.** The user may have made manual edits (checked boxes, added notes, etc.) that will be lost.

Before editing a PR body:
1. **Fetch current body first:** `gh pr view <number> --json body -q '.body'`
2. **Make incremental changes** - only modify the specific section you need to change
3. If adding a new section, append it rather than rewriting everything

# Claude Behavior

- When I reference a documentation file, you MUST read the ENTIRE file immediately, not in chunks
- Token minimization does NOT apply to reading referenced documentation
- Thoroughness trumps token efficiency for technical documentation
