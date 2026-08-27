# 119 - Gate runs the coverage slice on branches that compile no C#

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The pre-ready Gate always runs the coverage slice, even when the branch changed no compiled file.
That slice starts a SQL Server container and instruments every assembly, so it costs several
minutes and can say nothing about a change that compiled no C#.

## User story

As a developer finishing a tooling or documentation branch, I want the Gate to skip the checks that
cannot apply, so that I wait minutes instead of tens of minutes for a green verdict.

## Where this came from

Measured while shipping backlog item 118 (GitHub issue #339) on 2026-08-27. That branch changed only
`scripts/`, `tests/*.ps1`, `backlog/`, and `docs/`. It compiled no C# and still paid for the full
coverage slice.

## Measured cost

The five Gate steps on that branch:

| Step | Time |
|---|---|
| `dotnet build AHKFlowApp.slnx --configuration Release` | 16 s |
| `dotnet format AHKFlowApp.slnx --verify-no-changes` | seconds |
| `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` | 10.2 min (611 s, 42 suites) |
| `pwsh .\scripts\test-fast.ps1 -Mode Coverage` | several minutes |
| `git diff --check main...HEAD` | instant |

The Gate is defined at (`docs/development/testing-workflow.md:24`, "dotnet build AHKFlowApp.slnx --configuration Release").

Coverage mode hands off to `run-coverage.ps1` (`scripts/test-fast.ps1:168`, "& (Join-Path $PSScriptRoot 'run-coverage.ps1') -Configuration $Configuration").
That script starts a real SQL Server container, then runs `dotnet test` per project with coverlet
instrumentation (`scripts/run-coverage.ps1:79`, "dotnet test $project.Path --configuration $Configuration").

The PowerShell slice is a separate cost and is not in scope here. Four suites are 59% of its 611
seconds: `WorktreeMergedCleanup` 118.6 s, `AgentWorktreeGuard` 111.7 s, `CitationFreshness` 93 s,
`AgentPreCommitHook` 37 s. They are slow because each creates real git repositories and worktrees
on disk, and `run-powershell-suites.ps1` runs every suite as its own process, one after another.

## What CI already does, and the open question

`ci.yml` skips every .NET step when its `code` filter is false
(`.github/workflows/ci.yml:35`, "        if: steps.filter.outputs.code == 'false'").
The filter is three negative patterns under `predicate-quantifier: 'every'`
(`.github/workflows/ci.yml:28`, "          predicate-quantifier: 'every'").

**Measure this before designing anything.** With `every` and three negative patterns, `code` may
be false for a *mixed* pull request — one that changes a `.ps1` file and a `.md` file together —
because the `.md` file fails `!**/*.md`. If that reading is right, CI already skips the .NET
pipeline on branches like item 118's, and the local Gate is the only place paying the cost. If it
is wrong, CI pays it too and the fix belongs in both places.

Read the actual run for pull request #353 to settle it. Do not design from the YAML alone.

## Acceptance criteria

- [ ] A written statement of what `ci.yml`'s `code` filter evaluates to for a mixed pull request,
      backed by a real workflow run, not by reading the YAML.
- [ ] The Gate documentation names the condition under which the coverage slice may be skipped, in
      terms a reader can check against their own diff.
- [ ] Running the Gate on a branch that changed no compiled file completes without starting a SQL
      Server container.
- [ ] Running the Gate on a branch that changed one `.cs` file still runs the coverage slice.
- [ ] The skip is reported, not silent. A skipped slice prints why, so a green Gate never looks
      like it checked more than it did.
- [ ] `pwsh ./scripts/run-powershell-suites.ps1` passes.

## Out of scope

- Making the PowerShell suites faster. Four suites hold most of that time and each does real git
  work. That is its own item.
- Changing coverage thresholds, or which projects are measured.
- Running Gate steps in parallel.

## Notes / dependencies

- A skip decided from the diff is only as good as the base it compares against. Stacked work
  branches from another open branch, so the Gate must read the real base the same way it already
  does for `git diff --check` — see (`docs/development/testing-workflow.md:36`, "gh pr view --json baseRefName -q .baseRefName").
- This item was filed as 117 and renumbered to 119. `new-backlog-item.ps1` cannot see numbers on
  unmerged branches: 117 belongs to `fix/wt-removal-watcher-powershell-5` and 118 to
  `fix/wt-give-each-worktree-removal-its-abefe700`, and neither was merged when this was filed.
- Spec: none — decide at Plan whether the design needs one.
- Plan: none yet — this item is at Intake.
