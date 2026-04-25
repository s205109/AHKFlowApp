# Plan: Fix Documentation Inconsistencies

## Context

Local file fixes only. User will create the GitHub repo and configure branch protection themselves. No backlog items to implement — just fix inconsistencies across docs and backlog files.

## Changes

### 1. Rename + update backlog item 001
- Rename `001-create-backlog-in-azure.md` → `001-create-backlog-in-github.md`
- Replace all Azure/Azure DevOps references with GitHub
- Update acceptance criteria to reference GitHub Issues/Projects
- Update notes to reference `gh` CLI and `create-github-issues.ps1`

### 2. Fix github-setup.md
- Replace inline script block (lines 144-183) with cross-reference to `docs/scripts/create-github-issues.ps1`
- Add 2 missing epic labels to label creation block:
  - `epic: foundation` (used by backlog items 004, 017)
  - `epic: observability` (used by backlog item 011)
- Confirm owner `s205109` is already correct in the file

### 3. Commit
```
docs: fix Azure refs in backlog 001, sync github-setup with actual script
```

## Files
- `.claude/backlog/001-create-backlog-in-azure.md` → rename + edit
- `docs/development/github-setup.md` — edit

## Verification
- Grep for "Azure" in backlog 001 replacement file — should return 0 hits
- Grep for `.github\backlog` in github-setup.md — should return 0 hits (old inline script path removed)
- Count epic labels in github-setup.md — should be 12
