# Failure Modes Catalog

Each entry describes a known Claude failure mode with its symptom, the counter-instruction to include in enhanced prompts, and a concrete example pair.

---

## 1. shallow-investigation
**Categories:** all

**Symptom:** Skims the surface — reads only the diff, doesn't open surrounding files, doesn't trace call stacks, doesn't read PR descriptions or ticket context.

**Counter-instruction:** Before acting, read all relevant context. For changed functions, find their callers and callees. For PRs, read the description. For tickets, read the full thread. Understanding the full picture before responding is non-negotiable.

**Bad:** "This change looks fine, the method returns the correct type."
**Good:** "I traced `calculate_total` through its 3 callers in `InvoiceService`, `ReportBuilder`, and `BillingJob`. The new return type is compatible with `InvoiceService` and `ReportBuilder`, but `BillingJob#process` on line 45 passes the result to `format_currency` which expects a BigDecimal, not a Float. This will raise a TypeError in production."

---

## 2. blame-deflection
**Categories:** all

**Symptom:** When a test fails or something breaks, immediately claims it's a "pre-existing issue" or unrelated to current changes — without evidence.

**Counter-instruction:** If something fails, your changes caused it. The main branch is green. Investigate your own code changes first. Use `git diff` to see what you changed. Only after you have concrete proof (not speculation) that something is unrelated may you flag it — and you still need to fix it.

**Bad:** "This test failure appears to be pre-existing and unrelated to our changes."
**Good:** "The test `test_invoice_total_with_discount` is failing. I diffed my changes against main and found that I modified `calculate_discount` to return a percentage (0.15) instead of a multiplier (0.85). The test expects the multiplier format. Fixing `calculate_discount` to return `1 - discount_rate`."

---

## 3. framework-blame
**Categories:** all

**Symptom:** Blames the framework, library, or external tool for unexpected behavior without investigating own usage first.

**Counter-instruction:** Never blame a framework or library without evidence. If something behaves unexpectedly, investigate your own usage first — check the docs, read the source, add debugging output. Frameworks used by thousands of projects rarely have bugs in common operations. Your usage is almost certainly wrong.

**Bad:** "This appears to be a bug in Turbo Frames — the frame isn't reloading correctly."
**Good:** "I added `puts response.headers['Content-Type']` and the response is returning `text/html` without the turbo-frame tag wrapping. The issue is in our controller — we're rendering the full layout instead of just the frame partial. Adding `layout: false` and wrapping the response in a matching `<turbo-frame id='invoices'>` tag."

---

## 4. unsupported-claims
**Categories:** all

**Symptom:** Makes assertions about what code does, what caused a bug, or what will happen — without showing evidence. Presents speculation as fact.

**Counter-instruction:** Every claim needs evidence. If you say "this method returns X", show the code. If you say "this will fix the bug", explain the causal chain. If you say "this is safe", show what you checked. No claim without a citation (file path, line number, command output, or doc reference).

**Bad:** "The caching layer should handle this correctly."
**Good:** "I checked `CacheStore#fetch` at `app/services/cache_store.rb:34` — it uses `Rails.cache.fetch(key, expires_in: 1.hour)`. The key is built from `user_id` only, not `user_id + locale`. So when the locale changes, the stale cached value is returned. Adding `locale` to the cache key will fix this."

---

## 5. lazy-solutions
**Categories:** all

**Symptom:** Takes the easiest path instead of the correct one. Patches symptoms instead of fixing root causes. Adds workarounds instead of understanding the problem.

**Counter-instruction:** Choose the correct solution over the easy one. If the right fix requires reading 10 files or refactoring a method, do that. Patching symptoms creates tech debt and hides real problems. Ask: "Am I fixing the root cause, or just making the symptom go away?"

**Bad:** Adding `rescue nil` to suppress an error, or adding `.to_s` to avoid a type mismatch without understanding why the types differ.
**Good:** Tracing the type mismatch to its origin — a method 3 layers up that returns `nil` when the record doesn't exist — and adding proper nil handling at the source with a meaningful error message.

---

## 6. tdd-shortcuts
**Categories:** feature, bug-fix

**Symptom:** Writes application code before tests. Writes tests that pass immediately (not failing first). Skips branch creation. Jumps straight to implementation.

**Counter-instruction:** Follow strict TDD: (1) create a feature branch first, (2) write a test that fails for the right reason, (3) verify the failure, (4) only then write the minimum code to make it pass. If a test passes immediately, it doesn't prove anything — rewrite it to actually test the new behavior.

**Bad:** Writing the full `ExportService` class, then writing a test that calls it and passes on the first run.
**Good:** Writing `test_export_generates_csv_with_headers` first, running it, seeing it fail with `NameError: uninitialized constant ExportService`, then implementing `ExportService` incrementally until the test passes.

---

## 7. weak-test-coverage
**Categories:** pr-review, feature, bug-fix

**Symptom:** Tests use vague assertions (`.present?`, `.any?`, `> 0`), skip edge cases, don't test error paths, or test the happy path only. Test structure doesn't match the complexity of the code change.

**Counter-instruction:** Tests should use exact expected values calculated from known inputs. Every conditional branch in the code should have a corresponding test case. Test edge cases: nil inputs, empty collections, boundary values, error conditions. If the code has 5 branches, there should be at least 5 test cases.

**Bad:** `assert result.present?` or `assert_operator total, :>, 0`
**Good:** `expected = 3 * 25.50 # 3 hours at $25.50/hr` followed by `assert_in_delta 76.50, total`

---

## 8. missing-context
**Categories:** all

**Symptom:** Acts on incomplete information — makes changes without reading the file, answers questions without checking the code, reviews diffs without understanding the surrounding architecture.

**Counter-instruction:** Read before you act. Before modifying a file, read it. Before reviewing a diff, read the surrounding context of each changed file. Before answering a question about code, check the actual implementation. If you're unsure about something, investigate — don't guess.

**Bad:** "You should add a `validates :email, presence: true` to the User model." (Without checking if it already exists or if there's a custom validator.)
**Good:** "I read `app/models/user.rb` — there's already a `validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }` on line 12 which implicitly requires presence. Adding a separate `presence: true` would be redundant. The issue is actually in the form — the email field isn't marked as required, so users can submit blank values that get caught at the model layer instead of the form layer."

---

## 9. skipping-prerequisites
**Categories:** all

**Symptom:** Rushes past setup steps (branch creation, reading context, loading skills) straight into editing or implementation. Acknowledges the prerequisite exists but skips it anyway. Jumps to the "interesting" step in a workflow.

**Counter-instruction:** Complete all setup steps before touching any code. If the workflow says create a branch first, create the branch. If it says read the file first, read the file. If a workflow has steps 1-5, execute them in order — do not skip to step 3 because it's the interesting one.

**Bad:** Loading the git-town skill, acknowledging it says to create a branch, then immediately editing files on master anyway.
**Good:** Loading the git-town skill, running `git town hack feature/fix-query`, verifying you're on the new branch with `git branch --show-current`, then making edits.
