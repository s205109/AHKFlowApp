# 092 - Plans symlink test uses the first bash on PATH, which may be WSL

## Metadata

- **Epic**: Developer experience
- **Type**: Bug
- **Interfaces**: none (test suite)
- **Stage**: 0-intake

## Summary

`WorktreePlansSymlink.Tests.ps1` runs the file-suggestion script with whatever `bash` PowerShell
finds first. On a machine where that is the WSL `bash.exe`, the script runs inside WSL, cannot
see the Windows `rg`, and returns nothing. The test then fails on a machine where the feature
itself works.

## User story

As a developer running the PowerShell gate, I want the test to fail only when the code is wrong,
so that I do not have to tell a real failure apart from a failure of my own PATH.

## Detail

The test guards the live check on both tools being present:

```powershell
$hasBash = [bool] (Get-Command bash -ErrorAction SilentlyContinue)
$hasRg = [bool] (Get-Command rg -ErrorAction SilentlyContinue)
```

`tests/WorktreePlansSymlink.Tests.ps1:204-205`. Both lookups run in PowerShell, so they answer
for the Windows PATH. The script then runs under `bash` at `tests/WorktreePlansSymlink.Tests.ps1:211`.

When `bash` resolves to `C:\Windows\system32\bash.exe`, that is the WSL launcher, and the script
runs with the Linux PATH. `rg` installed on Windows is not on that PATH, so the picker lists
nothing and the assertion fails. The Git Bash at `/usr/bin/bash` does see the Windows `rg`, so
the same test passes on a machine where Git Bash comes first.

Reported by a reviewer on pull request #304, whose run showed 21 passed and 1 failed while the
same commit showed 22 passed on the author's machine. The branch touched neither the test nor the
script it exercises.

## Acceptance criteria

- [ ] The test picks a bash that can see the tools the script needs, or skips the live check
- [ ] The skip message says which host was rejected and why
- [ ] The test passes on a machine where WSL `bash.exe` comes first on PATH
- [ ] The test still fails when `.claude/file-suggestion.sh` really is broken

## Out of scope

- Changing `.claude/file-suggestion.sh` itself
- Making the repository work under WSL generally

## Notes / dependencies

- One option is to prefer the Git Bash next to `git.exe` over a bare `bash` lookup
- Another is to ask the chosen bash for `rg` — `bash -lc 'command -v rg'` — instead of asking
  PowerShell, so the guard and the run agree about the same PATH
