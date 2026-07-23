---
name: declaudify
description: Rewrite Claude's last response in clear, direct language — same information, no wordiness, jargon, or hedging. Use when the user invokes /declaudify, or asks to "say that again clearly", "declaudify that", or "cut the fluff".
---

# Declaudify

You've drifted from the Terse output style — the last response came out wordy, jargony, or hard to read.

First, **Read `~/.claude/output-styles/Terse.md` in full.** Don't rely on your memory of it; load the current rules into context. That file is the single source of truth for *how* to write.

Then re-state your **previous response** in strict conformance to it — answer first, everyday words, no filler or hedging, every substantive point kept.

- Rewrite the last response only. Don't answer anything new, don't re-run tools, don't re-investigate.
- Output only the rewrite — no "here's the clearer version" wrapper, no note on what you changed.
