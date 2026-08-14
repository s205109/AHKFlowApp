# 048 - Worktree setup must not strip comments from the JSON files it rewrites

## Metadata

- **Epic**: Developer experience
- **Type**: Fix
- **Interfaces**: UI
- **Stage**: 9-ship

## Summary

`setup-worktree-local-dev.ps1` rewrites several local configuration files so a worktree runs on its own ports. It parses each file as JSON and writes it back out. That round trip deletes every comment, adds a UTF-8 BOM, and reformats arrays. The port change is correct. The collateral damage is not.

## User story

As a developer working in an agent worktree, I want the setup script to change only the ports and names it needs to change, so that my `git diff` shows the isolation and nothing else.

## Evidence

Observed in the `fix/wt-no-auth-frontend-profile` worktree on 2026-08-01. `git diff` reported 37 changed lines across the five rewritten files. Only 5 of those lines were actual port or name rewrites.

Three separate kinds of damage:

- **Comments deleted.** `.vscode/launch.json` lost every comment, including ones that explain non-obvious configuration. Two examples, both gone: `// internalConsole is required for serverReadyAction: VS Code only scans the Debug Console for the pattern below (never an external/integrated terminal).` and `// Keep the UI debugger on an isolated Chrome profile. Reusing the default profile can hand startup off to an existing Chrome process and reintroduce cold-start crashes.`
- **UTF-8 BOM added.** Three files gained a BOM on their first line: `.vscode/launch.json`, `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`, and `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json`.
- **Arrays reformatted.** Single-line arrays became multi-line. For example `"Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.File" ]` in `src/Backend/AHKFlowApp.API/appsettings.json`.

These files are meant to stay uncommitted forever, so nothing is lost in git today. Two reasons it still matters:

1. The noise hides real mistakes. A worktree-local port value was committed by accident on `fix/wt-no-auth-frontend-profile` and had to be caught in review. A diff that showed only the 5 intended lines would have made that obvious.
2. If anyone does commit `.vscode/launch.json`, the deleted comments are gone for every contributor. The `serverReadyAction` comment records why a setting cannot be changed.

## Acceptance criteria

- [x] Running `setup-worktree-local-dev.ps1` in a fresh worktree leaves every comment in `.vscode/launch.json` intact
- [x] No rewritten file gains a UTF-8 BOM that it did not already have
- [x] Array formatting is unchanged in files the script rewrites
- [x] `git diff` in a fresh worktree shows only the port, database, and project-name changes
- [x] A regression test covers a rewrite of a JSON file that contains comments and a single-line array

## Out of scope

- Changing which files the script rewrites, or which values it writes
- Changing the port allocation scheme

## Notes / dependencies

- `scripts/setup-worktree-local-dev.ps1` is the file to change. The JSON helpers live in `scripts/worktree-json.common.ps1`.
- `.vscode/launch.json` is JSON with comments (JSONC). A plain JSON parser cannot preserve it. A targeted text edit, or a JSONC-aware writer, would.
- Existing PowerShell tests for this script: `tests/WorktreeLocalDevSetup.Tests.ps1`. CI runs it from the explicit list in `.github/workflows/ci.yml`.
