# Plan: Open Source Claude Code Permission Settings

## Context

Preparing AHKFlow for open source on GitHub. Need:
1. `settings.json` (committed) — safe defaults for unknown contributors
2. `settings.local.json` (gitignored) — bypass-permission setup for the repo owner

The current `settings.local.json` has a **structural bug**: `deny` and `hooks` are nested inside `permissions.permissions` (a second-level `permissions` key) instead of at the correct top-level. This means the deny rules and the dotnet format hook are currently silently ignored.

## How Settings Merge (not override)

Settings load: `user (~/.claude)` → `project (.claude/settings.json)` → `local (.claude/settings.local.json)`.

- **Scalars** (e.g. `defaultMode`): later file wins
- **Arrays** (e.g. `deny`, `allow`): **merge** — both lists are active simultaneously
- Result: local's `bypassPermissions` skips prompts, but settings.json's `deny` list still blocks dangerous commands

So `.claude/settings.json`'s deny rules protect ALL users — including you in bypass mode.

## What .gitignore Already Does

`.gitignore` already contains:
```
.claude/CLAUDE.local.md
.claude/settings.local.json
```
No changes needed there.

## Changes Required

### 1. Fix `.claude/settings.local.json` (fix structural bug)

Current (broken): `deny` and `hooks` are inside a nested `"permissions"` key inside `"permissions"`. Correct structure:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": [
      "Bash(rm -rf*)",
      "Bash(mkfs*)",
      "Bash(dd*)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'FILE=$(jq -r \".tool_input.file_path // empty\"); echo \"$FILE\" | grep -q \"\\.cs$\" && dotnet format \"C:/Dev/segocom-github/AHKFlow\" 2>/dev/null || true'",
            "timeout": 60,
            "statusMessage": "Running dotnet format..."
          }
        ]
      }
    ]
  }
}
```

Note: No need to repeat denies already in `settings.json` — they merge automatically.

### 2. Improve `.claude/settings.json` — add missing dangerous denies

`rm -rf*` is absent from the current deny list. This is a gap that affects all contributors.
Also add `mkfs*` and `dd*` as they are universally destructive.

Add to the `deny` array:
```json
"Bash(rm -rf*)",
"Bash(rm -r *)",
"Bash(mkfs*)",
"Bash(dd if=*)"
```

### 3. Add dotnet commands to `.claude/settings.json` allow list (contributor UX)

Contributors will need dotnet commands. With `defaultMode: "default"` (ask), they'd be prompted every time. Add standard .NET dev commands to allow:

```json
"Bash(dotnet build*)",
"Bash(dotnet test*)",
"Bash(dotnet run*)",
"Bash(dotnet restore*)",
"Bash(dotnet format*)",
"Bash(dotnet ef*)",
"Bash(dotnet add*)",
"Bash(dotnet list*)",
"Bash(docker compose*)"
```

## Files to Modify

| File | Git | Change |
|------|-----|--------|
| [.claude/settings.json](c:\Dev\segocom-github\AHKFlow\.claude\settings.json) | Committed | Add missing dangerous denies + dotnet allows |
| [.claude/settings.local.json](c:\Dev\segocom-github\AHKFlow\.claude\settings.local.json) | Gitignored | Fix structural bug (deny and hooks at wrong nesting level) |

## Verification

After applying:
1. Confirm `settings.local.json` parses as valid JSON with correct structure
2. Confirm deny entries like `rm -rf*` are at `permissions.deny[]`, not `permissions.permissions.deny[]`
3. Confirm hooks are at the top-level `hooks` key, not inside `permissions`
4. Open a Claude Code session and verify bypass mode is active (no prompts for `dotnet build`)
5. Verify `git push --force` is still blocked (deny from settings.json merges into local session)

## Unresolved Questions

- Should `docker compose*` be allowed without prompting? It spins up containers and modifies system state.
- Should `dotnet ef*` migrations be allowed? They modify the database schema.
