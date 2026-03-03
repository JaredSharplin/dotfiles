# Ruby Scripting Patterns

## JSON

```ruby
require 'json'

# Parse with symbol keys
data = JSON.parse(output, symbolize_names: true)

# Safe nested access
data.dig(:author, :login)

# Pretty output
puts JSON.pretty_generate(data)

# Error handling
begin
  data = JSON.parse(output, symbolize_names: true)
rescue JSON::ParserError => e
  abort "Invalid JSON: #{e.message}"
end
```

## Heredocs for prompts

Squiggly heredoc strips leading indentation:

```ruby
prompt = <<~PROMPT
  Check these tasks:
  #{active_tasks}

  For each one, do the following...
PROMPT
```

Disable interpolation with single-quoted delimiter:

```ruby
template = <<~'SQL'
  SELECT * FROM users WHERE id = #{placeholder}
SQL
```

## OptionParser

```ruby
require 'optparse'

options = { verbose: false }

OptionParser.new do |o|
  o.banner = "Usage: script.rb [options]"
  o.on('-v', '--verbose')       { options[:verbose] = true }
  o.on('-n NUMBER', Integer)    { |n| options[:number] = n }
  o.on('-h', '--help')          { puts o; exit }
end.parse!

# Remaining positional args are still in ARGV after parse!
```

## Ruby 3.x pattern matching

Destructure CLI JSON output cleanly:

```ruby
case JSON.parse(output, symbolize_names: true)
in { state: "MERGED" } then mark_done(task_id)
in { state: "OPEN" }   then :skip
in { state: }          then abort "Unexpected state: #{state}"
end

# One-line extraction
gh_output => { number:, title:, url: }
```

Guard clauses:

```ruby
case task
in { status: "active", project_dir: dir } if dir.start_with?(SLOT_BASE)
  process_slot_task(task)
end
```

## Parallel subprocess calls

```ruby
require 'open3'

results = pr_numbers.map do |n|
  Thread.new { Open3.capture3("gh", "pr", "view", n.to_s, "--json", "state") }
end.map(&:value)
```

## Building Claude prompts

Collect task context then interpolate:

```ruby
tasks = JSON.parse(`task export`, symbolize_names: true)
  .select { _1[:status].match?(/pending|active/) }
  .map { "  ##{_1[:id]}: #{_1[:description]}" }
  .join("\n")

prompt = <<~PROMPT
  Current tasks:
  #{tasks}

  Do the following...
PROMPT

exec("claude", "--dangerously-skip-permissions", prompt)
```

Use `exec` (not `system`) when launching Claude as the final step — replaces the process rather than forking.

## Charm Ruby (TUI components)

[charm-ruby.dev](https://charm-ruby.dev) — terminal UI gems when scripts need interactivity:

- **Huh?** — forms: `Input`, `Select`, `Confirm` — replaces raw `$stdin.gets` prompts
- **Bubbles** — spinner while waiting on slow CLI calls, progress bars
- **Lipgloss** — styled output with colors, borders, padding
- **Gum** — idiomatic shell-script-friendly wrappers for the above

```ruby
# Confirm before destructive action
require 'charm/huh'
confirmed = Huh::Confirm.new(title: "Mark task done?").run
```

Worth adding when a script has user-facing prompts or long-running operations.

## Common gotchas

**`$?` changes after every command** — capture immediately:
```ruby
system("cmd")
status = $?.exitstatus  # store before next command
```

**Bundler env leaks into subprocesses** — isolate when spawning other Ruby scripts:
```ruby
require 'bundler'
Bundler.with_original_env { system("other-ruby-script") }
```

**String encoding** — captured output may need coercing:
```ruby
stdout.force_encoding('UTF-8')
```

**`Open3.popen3` deadlock** — stdout fills buffer while you're waiting to read stderr. Use `capture3` unless you specifically need streaming.
