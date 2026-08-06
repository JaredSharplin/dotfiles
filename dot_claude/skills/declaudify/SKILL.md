---
name: declaudify
description: Re-say Claude's last response in clear, direct language — cut the wordiness, or supply the context that was missing. Use when the user invokes /declaudify, or says "say that again clearly", "cut the fluff", "wait, what?", "I don't follow", "that didn't land".
---

# Declaudify

1. Work out which way it failed, then rewrite for that:
   - **Too wordy** — the point was there, buried. Answer first, everyday words, no filler or hedging.
   - **Didn't land** — the reader is missing background you assumed. Supply that background, then the point.
2. Write it in [ASD-STE100 Simplified Technical English](https://en.wikipedia.org/wiki/Simplified_Technical_English): one meaning per word, short sentences, active voice, no metaphor.
3. Two or three sentences — up to five when supplying missing context.
4. Rewrite the last response only. Don't answer anything new, don't re-run tools, don't re-investigate.
5. Output only the rewrite — no wrapper, no note on what you changed.
