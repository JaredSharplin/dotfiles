---
name: ruby-scripting
description: Patterns and conventions for writing standalone Ruby scripts — dotfiles tools, automation scripts, CLI wrappers. Use when writing or editing scripts in ~/.config/task/scripts/, ~/bin/, or any non-Rails Ruby script that calls CLI tools, parses JSON, or builds prompts. Triggers include "write a script", "ruby script", "automate", "task-sync", "pr-review", or any request to create a new dotfiles tool.
---

# Ruby Scripting

## Script header

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
```

Always both lines. `frozen_string_literal` prevents accidental mutation and is slightly more memory efficient.

## Subprocess selection

| Need | Use |
|------|-----|
| Simple stdout, trusted input | `` `cmd` `` or `%x(cmd)` |
| Fire-and-forget, stream to terminal | `system("cmd", exception: true)` |
| Capture stdout + stderr + exit status | `Open3.capture3(*args)` |
| Stream large output incrementally | `Open3.popen3` (read both streams concurrently) |

**Default to `Open3.capture3` with array args** — no shell interpolation, proper exit status:

```ruby
require 'open3'

def run(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{stderr.strip}" unless status.success?
  stdout.strip
end

run("gh", "pr", "view", pr_number, "--json", "state")
```

## Key stdlib

```ruby
require 'open3'    # subprocesses
require 'json'     # JSON.parse / .to_json
require 'optparse' # CLI argument parsing
```

## Exit conventions

```ruby
abort "message"  # prints to stderr, exits 1
exit 0           # success
```

## Detailed patterns

See `references/patterns.md` for:
- JSON handling
- Heredocs for prompts
- OptionParser argument parsing
- Ruby 3.x pattern matching in scripts
- Charm Ruby (TUI components)
- Common gotchas
