# Debug Patterns for Rails

Strategic puts debugging to reveal actual runtime behavior. All statements use the `[DEBUG tdd-bug-fix]` prefix for easy identification and removal.

## Prefix Format

```ruby
puts "[DEBUG tdd-bug-fix] ClassName#method_name: description=#{value.inspect}"
```

Always use `.inspect` on values to distinguish `nil` from `""` from `0` from `false`.

## Placement Patterns

### Method Entry and Exit

```ruby
def calculate_total(items)
  puts "[DEBUG tdd-bug-fix] Order#calculate_total: items.count=#{items.count}"
  # ... existing code ...
  puts "[DEBUG tdd-bug-fix] Order#calculate_total: result=#{result.inspect}"
  result
end
```

### Conditional Branches

```ruby
if employee.full_time?
  puts "[DEBUG tdd-bug-fix] PayCalculator#rate: full_time branch, employee_id=#{employee.id}"
  base_rate
else
  puts "[DEBUG tdd-bug-fix] PayCalculator#rate: part_time branch, employee_id=#{employee.id}"
  hourly_rate
end
```

### ActiveRecord Queries

```ruby
scope = User.where(active: true).joins(:roles)
puts "[DEBUG tdd-bug-fix] scope.to_sql=#{scope.to_sql}"
puts "[DEBUG tdd-bug-fix] scope.count=#{scope.count}"
```

### Calculation Intermediates

```ruby
hours = timesheet.total_hours
puts "[DEBUG tdd-bug-fix] hours=#{hours.inspect}"
rate = pay_rate.amount
puts "[DEBUG tdd-bug-fix] rate=#{rate.inspect}"
multiplier = overtime? ? 1.5 : 1.0
puts "[DEBUG tdd-bug-fix] multiplier=#{multiplier.inspect}"
total = hours * rate * multiplier
puts "[DEBUG tdd-bug-fix] total=#{total.inspect}"
```

### Nil Propagation

When debugging unexpected nils, trace the chain:

```ruby
puts "[DEBUG tdd-bug-fix] user=#{user.inspect}"
puts "[DEBUG tdd-bug-fix] user.organisation=#{user.organisation.inspect}"
puts "[DEBUG tdd-bug-fix] user.organisation.billing=#{user.organisation&.billing_object.inspect}"
```

### Callback/Hook Execution

```ruby
before_save :normalize_data

def normalize_data
  puts "[DEBUG tdd-bug-fix] #{self.class}#normalize_data called, changes=#{changes.inspect}"
end
```

## Removal

After the fix is implemented and tests pass, remove all debug statements:

1. Search: `Grep` for `[DEBUG tdd-bug-fix]` across the codebase
2. Remove each line using the `Edit` tool
3. Verify no debug statements remain before committing
