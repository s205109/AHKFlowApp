# Plan: Claude Code Permission Settings for Open Source

## Context

AHKFlow is being made public on GitHub. Claude Code settings need two layers:
- `settings.json` (committed) — secure defaults for any GitHub contributor
- `settings.local.json` (gitignored) — permissive setup for the owner's laptop

Currently `settings.local.json` is NOT in `.gitignore` — it would be committed as-is, which is a bug.

---

## How settings.json and settings.local.json Interact

This is the key fact to understand before making changes:

| Setting type | Behavior |
|---|---|
| `defaultMode` (scalar) | Local **overrides** project |
| `allow` / `deny` (arrays) | **Merged** (union) — local adds to project, cannot remove entries |
| `hooks` | Merged by event type |

**Practical implication:** You cannot un-deny something in `settings.local.json` that's denied in `settings.json`. You can only add more denies or allows. For `defaultMode`, local wins completely.

---

## Recommended Architecture

```
settings.json       → committed, secure defaults for GitHub contributors
settings.local.json → gitignored, bypassPermissions + owner-specific allows
```

The "safety net" pattern: local sets `bypassPermissions` (no prompts), the shared deny list still blocks explicitly dangerous commands. Deny rules persist in both modes.

---

## Changes

### 1. `.gitignore` — Add missing entry

`settings.local.json` is currently tracked by git. Add:
```
.claude/settings.local.json
```

### 2. `settings.json` — Harden for public use

**File:** `.claude/settings.json`

Remove `"Bash(rm *)"` from `allow`. This is the only risky entry in the public file — rm without flags can still delete individual files. The user already has it in `settings.local.json`.

Keep everything else:
- `defaultMode: "default"` — prompts for unlisted actions (correct for public contributors)
- Deny list — strong, covers all the dangerous patterns
- File-level denies for `.env*`, `*.pem`, `*.key`, `*secret*`, `*credential*`
- Hooks, plugins, MCP servers (all safe to share; MCP requires each user's own auth)

### 3. `settings.local.json` — Add bypassPermissions

**File:** `.claude/settings.local.json`

Add `"defaultMode": "bypassPermissions"` inside the `permissions` object. This overrides the `"default"` from settings.json, eliminating prompts on the owner's machine.

The existing local allows (git push, dotnet, docker, rm) remain.
The deny rules from settings.json still apply via array merging — git push --force, sudo, etc. remain blocked.

---

## Final State Summary

**settings.json (committed):**
- `defaultMode: "default"` — contributors get prompted for unlisted actions
- Allow: read ops, git read/write (non-destructive), gh CLI, dotnet build/test, echo, ls, PowerShell safe ops
- Deny: force push, hard reset, git clean, curl, wget, ssh, scp, sudo, chmod 777, kill -9, pkill, PowerShell dangerous ops, all secret file reads/edits

**settings.local.json (gitignored):**
- `defaultMode: "bypassPermissions"` — owner gets no prompts
- Additional allows: git push, dotnet ef/tool/new/add/remove, docker, rm
- Deny: `[]` (inherits all denies from settings.json via merge)

---

## Verification

1. Confirm `settings.local.json` is gitignored: `git status --short` should not show it
2. Confirm settings.json has no `rm` in allow list
3. Confirm settings.local.json has `bypassPermissions`
4. Open a new Claude Code session — should not prompt for routine operations (local bypass works)
5. Verify dangerous commands still blocked: attempt `git push --force` — should be denied

---

## Unresolved Questions

- The `mcpServers.github` entry in settings.json points to GitHub Copilot MCP. Public contributors won't have auth for this — is it OK to leave it (it'll just fail silently for them) or should it be removed/documented?
