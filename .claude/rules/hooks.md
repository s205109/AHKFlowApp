---
alwaysApply: true
description: >
  Enforces correct interaction with pre-commit, post-edit, and post-test hooks.
---

# Hook Rules

- Auto-accept post-edit format hooks. Don't revert formatting changes applied by hooks.
- Never skip pre-commit hooks with `--no-verify`. Investigate and fix the root cause when blocked.
- Don't interfere with hook configuration — hooks run automatically via plugin settings.
