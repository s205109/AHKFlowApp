# Plan: Reconcile Three Settings Files

## Context
After a git reset, `~/.claude/settings.json` (global) reverted to a minimal state. The pre-reset version had project-specific content mixed in (dotnet bash allows, project plugins, github MCP) — that content correctly belongs in project settings and is already there. But the reset also removed universal personal safety denies and preferences that DO belong in global.

Goal: restore only the globally-appropriate content to `~/.claude/settings.json`, keep project settings as-is, keep local settings as-is.

## Files involved
- `~/.claude/settings.json` — needs updating (missing deny rules + personal pref)
- `c:\Dev\segocom-github\AHKFlow\.claude\settings.json` — no changes needed
- `c:\Dev\segocom-github\AHKFlow\.claude\settings.local.json` — no changes needed

## Current state analysis

### Global (`~/.claude/settings.json`)
```
allow: Skill(update-config), Skill(update-config:*)
deny:  Read(.env*), Read(secrets.*), Read(appsettings.Production.*), Read(appsettings.Staging.*)
       Bash(rm -rf*), Bash(rm -r *), Bash(sudo *),
       Bash(git push --force*), Bash(git reset --hard *),
       Bash(pwsh -Command Remove-*), Bash(pwsh -Command Set-ExecutionPolicy*)
```
**Missing from pre-reset** (personal/universal safety rules):
- `Bash(git push*)` — deny all push globally (personal safety net)
- `Bash(git merge*)`, `Bash(git rebase*)`, `Bash(git cherry-pick*)` — prevent history rewrites
- `Bash(git clean -fd*)`, `Bash(git remote remove*)` — destructive git
- `Bash(source *)`, `Bash(. *)` — script injection
- `Bash(del /s*)`, `Bash(rmdir /s*)`, `Bash(format *)` — Windows destructive
- `Bash(curl * | bash*)`, `Bash(wget * | bash*)` — remote script execution
- `Bash(docker system prune*)` and variants
- `Edit(**/.env)`, `Edit(**/.env.*)`, `Edit(**/appsettings.Production.json)`, `Edit(**/appsettings.Staging.json)`, `Edit(**/secrets.json)`, `Edit(**/*.pfx)`, `Edit(**/*.pem)`, `Edit(**/*.key)`, `Edit(**/*.p12)` — sensitive file protection
- `skipDangerousModePermissionPrompt: true` — personal pref

### Project (`settings.json`) — no changes needed
Comprehensive allow list (dotnet, git, gh, docker, shell, WebFetch). Good deny list.
`defaultMode: "default"` — correct for open source contributors.

### Local (`settings.local.json`) — no changes needed
`defaultMode: "acceptEdits"`, minimal personal allow (2 WebFetch), safety deny, format hook.

## Separation of concerns (after fix)

| Concern | Global | Project | Local |
|---|---|---|---|
| defaultMode | not set | "default" (cloner safety) | "acceptEdits" (owner UX) |
| dotnet/git/docker allows | ✗ | ✓ | via merge |
| Personal hooks/plugins/statusLine | ✓ | ✗ | ✗ |
| Universal safety denies | ✓ | some overlap | minimal |
| Project safety denies | ✗ | ✓ | via merge |
| Sensitive file protection (Edit/Read) | ✓ | ✓ | via merge |
| skipDangerousModePermissionPrompt | ✓ | ✗ | ✗ |

Overlapping deny rules across scopes are **harmless** (defence in depth).

## Decisions (resolved via grill-me)
- **`git push*` in global deny**: YES — universal safety net, all projects on this machine
- **`git merge/rebase/cherry-pick` in global deny**: NO — workflow-dependent, keep project-only (prompts via `defaultMode: "default"` for cloners)
- **Edit deny for sensitive files in global**: YES — universal protection regardless of project
- **`skipDangerousModePermissionPrompt`**: YES — restore personal pref

## Final global settings (after applying all recommendations)

```json
{
  "permissions": {
    "allow": [
      "Skill(update-config)",
      "Skill(update-config:*)"
    ],
    "deny": [
      "Read(**/.env*)",
      "Read(**/secrets.*)",
      "Read(**/appsettings.Production.*)",
      "Read(**/appsettings.Staging.*)",
      "Bash(rm -rf*)",
      "Bash(rm -r *)",
      "Bash(sudo *)",
      "Bash(git push*)",
      "Bash(git push --force*)",
      "Bash(git reset --hard *)",
      "Bash(git clean -fd*)",
      "Bash(git remote remove*)",
      "Bash(source *)",
      "Bash(. *)",
      "Bash(del /s*)",
      "Bash(rmdir /s*)",
      "Bash(format *)",
      "Bash(curl * | bash*)",
      "Bash(wget * | bash*)",
      "Bash(docker system prune*)",
      "Bash(docker image prune*)",
      "Bash(docker volume prune*)",
      "Bash(docker container prune*)",
      "Bash(pwsh -Command Remove-*)",
      "Bash(pwsh -Command Set-ExecutionPolicy*)",
      "Edit(**/.env)",
      "Edit(**/.env.*)",
      "Edit(**/appsettings.Production.json)",
      "Edit(**/appsettings.Staging.json)",
      "Edit(**/secrets.json)",
      "Edit(**/*.pfx)",
      "Edit(**/*.pem)",
      "Edit(**/*.key)",
      "Edit(**/*.p12)"
    ]
  },
  "hooks": { /* unchanged */ },
  "statusLine": { /* unchanged */ },
  "enabledPlugins": { /* unchanged */ },
  "extraKnownMarketplaces": { /* unchanged */ },
  "effortLevel": "medium",
  "autoUpdatesChannel": "latest",
  "skipDangerousModePermissionPrompt": true
}
```

## Verification
- `git push` → blocked (global deny)
- `git push --force` → blocked (global deny, redundant but harmless)
- `git status` → allowed (project allow, no prompt in acceptEdits)
- `dotnet build` → allowed (project allow, no prompt)
- Edit `.env` → blocked (global + project deny)
- `curl something` → blocked (project deny)
- `curl something | bash` → blocked (global deny)
- New project without settings.json → global denies still protect

Note: `Bash(git push --force*)` is now redundant (covered by `Bash(git push*)`), but kept for clarity.
