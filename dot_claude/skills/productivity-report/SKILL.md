---
name: productivity-report
description: >
  End-of-day reflection over the productivity log written by /productivity-summary.
  Renders a plain-text activity-by-hour view, peak window, day totals (commits, PRs
  merged, reviews given), and focus split across worktrees. Use when the user invokes
  /productivity-report, asks "how did my day go", "when was I most productive", or
  wants to reflect on the day's work. Pass a date (YYYY-MM-DD) to report on a past day.
---

# Productivity report

Reads `~/.local/share/productivity/<date>.jsonl` and prints a text reflection. The script does the
whole job — run it and let its output stand; add at most a one or two line read of the day if it's
genuinely useful (e.g. "peak was mid-morning, quiet after lunch").

## Run

```bash
~/.claude/skills/productivity-summary/report.rb            # today
~/.claude/skills/productivity-summary/report.rb 2026-07-11 # a past day
```

The renderer lives with the collector under `productivity-summary/report.rb`; this skill is just the
entry point. If the log doesn't exist yet, it means `/productivity-summary` hasn't run today — say
so rather than fabricating a report.
