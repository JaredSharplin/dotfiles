# Investigation Checklist

Systematic evidence gathering before any hypothesis is formed.

## 1. Extract Ticket Information

From the Linear ticket, identify and record:

- **Steps to reproduce** — exact sequence of actions
- **Expected behavior** — what should happen
- **Actual behavior** — what happens instead
- **Error messages** — exact text, stack traces, log snippets
- **Customer data** — org IDs, user IDs, record IDs, dates mentioned
- **Frequency** — always, intermittent, specific conditions

If the ticket is vague on any of these, note what's missing. Do not fill gaps with assumptions.

## 2. Corroborate Claims Against Code

For each claim in the ticket, find the corresponding code path:

1. Trace the user action to a controller/route
2. Follow the code path through models/services
3. Verify the claimed behavior is plausible given the code
4. Note any discrepancies between ticket description and code logic

## 3. Check Recent Changes

```bash
git log --oneline -20 -- <affected_files>
git log --oneline --since="2 weeks ago" -- <affected_directory>
```

Look for:
- Recent commits that touched the affected code
- Refactors that may have changed behavior
- New features that interact with the affected area

## 4. Red Flags

| Ticket says... | Investigate... |
|---|---|
| "Used to work" / "Regression" | `git log` for recent changes, `git bisect` if needed |
| "Intermittent" / "Sometimes" | Race conditions, caching, timezone-dependent logic, order-dependent queries |
| "Only some users" / "Only some orgs" | Feature flags, permissions, conditional logic based on org/user attributes |
| "After upgrade" / "After deploy" | Dependency changes, migration side effects, config changes |
| "Wrong calculation" | Rounding, integer vs float division, nil propagation, currency handling |

## 5. Console Verification

Only when the ticket references specific customer data:

1. Load `dev-console` skill first
2. Batch all queries in a single console session
3. Verify the exact data conditions described in the ticket exist
4. Record actual values — these become test fixture data
5. Check associated records (belongs_to, has_many) for unexpected state

Example queries:
```ruby
record = Model.find(id)
puts record.attributes.inspect
puts record.association.attributes.inspect
```

## 6. Existing Test Coverage

Check what tests already exist for the affected code:

- Find test files: `Glob` for `test/**/*<model_name>*_test.rb`
- Check if any tests cover the specific scenario
- Note gaps — these inform what new tests to write
- If existing tests pass, the bug is in an untested code path
