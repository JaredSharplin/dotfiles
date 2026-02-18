---
name: rubycritic
description: Analyze Ruby code quality using RubyCritic (Flog complexity + Flay duplication + Reek smells). Use when the user asks to analyze code quality, check complexity, find code smells, or run rubycritic. Triggers include "rubycritic", "code quality", "complexity analysis", "code smells", or "flog/flay/reek". (user)
---

# RubyCritic - Ruby Code Quality Analysis

Analyze Ruby files using RubyCritic, which combines Flog (complexity), Flay (duplication), and Reek (code smells).

## Workflow

### Step 1 - Identify files

If the user provided specific files or directories, use those.

Otherwise, detect changed Ruby files on the current branch vs master:
```bash
git diff master --name-only -- '*.rb' | grep -v '^test/'
```

If no Ruby files are found, inform the user and stop.

### Step 2 - Run analysis

Run RubyCritic with console and JSON output:
```bash
rubycritic --format json --format console --no-browser <files>
```

Read `tmp/rubycritic/report.json` for structured data.

### Step 3 - Branch comparison

Skip if the user provided specific files as arguments.

Run CI mode to detect regressions against master, passing the same filtered file list from Step 1:
```bash
rubycritic --mode-ci master --format console --no-browser <files>
```

### Step 4 - Present results

**Per-file summary table:**
- File path, Rating (A-F), Score, Complexity, Duplication count, Smell count

**Regressions (from branch comparison):**
- Files whose scores degraded vs master
- Overall score change

**Actionable items:**
- List specific code smells with `file:line` references
- Flag any files rated D or F as needing immediate attention
- Group smells by type (complexity, duplication, code smells)
- Suggest concrete improvements for the worst offenders
