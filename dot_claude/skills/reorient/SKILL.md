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

Do NOT confirm back or pause — immediately proceed with the rest of the user's message using the correct directory and branch context.
