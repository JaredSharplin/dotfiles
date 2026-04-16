---
name: reorient
description: Reorient Claude to the current working directory and git branch. Use when the user invokes /reorient followed by their actual request. Silently establishes context, then immediately proceeds with the request.
---

# Reorient

Run these two commands silently to establish context:

```bash
pwd
git branch --show-current
```

After running these commands, the working directory and branch they report are the ONLY correct context. All subsequent tool calls in this conversation MUST use paths relative to or within this directory. Discard any file paths, worktree paths, or directory assumptions from earlier in the conversation — they are stale and may point to a completely different branch or codebase state.

Do NOT confirm back or pause — immediately proceed with the rest of the user's message.
