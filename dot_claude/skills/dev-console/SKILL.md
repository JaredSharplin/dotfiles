---
name: dev-console
description: Use this skill when you need to query the shared developer database using bin/dev console. Contains safety rules, usage patterns, and examples for READ-ONLY database queries. (user)
---

# bin/dev console - READ-ONLY Database Queries

`bin/dev console` connects to a **SHARED DATABASE** used by ALL developers. This skill documents safe usage patterns.

## Critical Safety Rules

1. **READ-ONLY OPERATIONS ONLY** - You may ONLY perform SELECT queries and read operations
2. **ABSOLUTELY NO WRITES** - Never use `.save`, `.update`, `.create`, `.delete`, `.destroy`, or any mutation methods
3. **NO TESTING** - Tests MUST be run locally using `bin/rails test` - NEVER through `bin/dev console`

## When to Use

Use ONLY for:
- Investigating production-like data issues
- Querying database state for debugging
- Reading PaperTrail versions
- Examining actual record values

## Performance: Batch Commands

Starting the remote console is slow (~10-15 seconds). Batch multiple queries in one session:

**Wrong (slow - multiple startups):**
```bash
echo "puts 1 + 1" | bin/dev console
echo "puts 2 + 2" | bin/dev console
```

**Correct (fast - single startup):**
```bash
cat <<'EOF' | bin/dev console
puts 1 + 1
puts 2 + 2
exit
EOF
```

Or use a temporary file:
```bash
cat > /tmp/query.rb <<'EOF'
org = Organisation.find(237158)
billing = org.billing_object
puts "invoiced_annually: #{billing.invoiced_annually}"
puts "next_invoice_date: #{billing.next_invoice_date}"
exit
EOF

cat /tmp/query.rb | bin/dev console
```

## Example Queries

```bash
# Query organization billing state
cat <<'EOF' | bin/dev console
org = Organisation.find(237158)
billing = org.billing_object
puts "State: #{billing.invoiced_annually ? 'Annual' : 'Monthly'}"
puts "Next invoice: #{billing.next_invoice_date}"
exit
EOF

# Check PaperTrail versions
cat <<'EOF' | bin/dev console
billing = Organisation.find(237158).billing_object
versions = billing.versions.order(created_at: :desc).limit(5)
versions.each { |v| puts "#{v.created_at}: #{v.audit_trail_name}" }
exit
EOF
```

## Forbidden Operations

Never do ANY of these:
```ruby
# NO SAVES
billing.update(next_invoice_date: Date.today)
billing.save

# NO CREATES
Organisation.create(name: "Test")

# NO DELETES
billing.destroy

# NO MUTATIONS
billing.next_invoice_date = Date.today
billing.save!
```

## Always Use `exit`

Always end queries with `exit` to cleanly close the console:
```bash
cat <<'EOF' | bin/dev console
# your queries here
exit
EOF
```
