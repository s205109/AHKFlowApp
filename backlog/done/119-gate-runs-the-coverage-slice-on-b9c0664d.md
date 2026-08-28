# 119 - Gate runs the coverage slice on branches that compile no C#

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

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

Coverage mode hands off to `run-coverage.ps1` (`scripts/test-fast.ps1:199`, "& (Join-Path $PSScriptRoot 'run-coverage.ps1') -Configuration $Configuration").
That script starts a real SQL Server container, then runs `dotnet test` per project with coverlet
instrumentation (`scripts/run-coverage.ps1:79`, "dotnet test $project.Path --configuration $Configuration").

The PowerShell slice is a separate cost and is not in scope here. Four suites are 59% of its 611
seconds: `WorktreeMergedCleanup` 118.6 s, `AgentWorktreeGuard` 111.7 s, `CitationFreshness` 93 s,
`AgentPreCommitHook` 37 s. They are slow because each creates real git repositories and worktrees
on disk, and `run-powershell-suites.ps1` runs every suite as its own process, one after another.

## What CI does — measured, not read from the YAML

`ci.yml` skips every .NET step when its `code` filter is false
(`.github/workflows/ci.yml:50`, "        if: steps.filter.outputs.code == 'false'").
The filter is three negative patterns under `predicate-quantifier: 'every'`
(`.github/workflows/ci.yml:47`, "          predicate-quantifier: 'every'").

Reading that config, it looked possible that `code` would be false for a *mixed* pull request —
one changing a `.ps1` file and a `.md` file together — because the `.md` file fails `!**/*.md`.

**That reading is wrong.** Pull request #353 changed `scripts/`, `tests/*.ps1`, `backlog/*.md`, and
`docs/`. Its `build-test` job, run 33078712913, reports:

```
success   Detect non-docs changes
skipped   Skip notice (docs-only PR)
success   Run dotnet restore
success   Run dotnet build --configuration Release --no-restore
success   Test with coverage
success   Merge coverage reports
```

The skip notice was skipped, so `code` was `true`, and the full .NET pipeline ran — including
coverage — for a branch that compiled no C#.

So CI pays this cost as well as the local Gate. Any fix has to cover both, and the two must agree
on the condition, or a branch will be skipped in one place and measured in the other.

Do not design from the YAML alone. This answer came from a real run.

## Acceptance criteria

- [x] A written statement of what `ci.yml`'s `code` filter evaluates to for a mixed pull request,
      backed by a real workflow run, not by reading the YAML. Answered at Intake from run
      33078712913: `code` was `true` and the full .NET pipeline ran. See the section above.
- [x] The Gate documentation names the condition under which the coverage slice may be skipped, in
      terms a reader can check against their own diff.
- [x] Running the Gate on a branch whose changed paths the filter excludes in full completes
      without starting a SQL Server container. Reworded during Execute: "changed no compiled file"
      was false as a rule, because `infra/**` compiles nothing and still runs the slice.
- [x] Running the Gate on a branch that changed one `.cs` file still runs the coverage slice.
- [x] `ci.yml` and the Gate use the same `code` exclusions for the same committed diff. The Gate
      may additionally run for `coverage-tooling`, so it can be stricter than CI but never
      looser.
- [x] The skip is reported, not silent. A skipped slice prints why, so a green Gate never looks
      like it checked more than it did.
- [x] `pwsh ./scripts/run-powershell-suites.ps1` passes.

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
- Spec: none — the design fits inside the plan. Decided at Plan.
- Plan: `docs/superpowers/plans/2026-08-27-gate-coverage-skip-plan-119.md`
- Criterion 5 was reworded during Execute. It said `ci.yml` and the Gate "never disagree about one
  branch", and the design's `coverage-tooling` key makes that false on seven paths. A change to
  `scripts/run-coverage.ps1` runs the slice locally and skips the .NET steps in CI. That is the
  right answer in both places, so the criterion now states the one-directional difference instead.
  Editing it is honest; ticking the original wording would not have been.
- This branch cannot demonstrate the CI skip. It adds `.github/code-paths-filter.yml` and edits
  `.github/workflows/ci.yml`. No pattern excludes a `.yml` file under `.github/`, so `code` is
  `true` here and the full .NET pipeline runs. A file ending in lowercase `.md` under `.github/`
  is a different case: the repository-wide `!**/*.md` pattern excludes it, the same as a lowercase
  `.md` file anywhere else. Matching is case-sensitive, so `.MD` and `.Md` are not excluded and
  still count as code. Every other file under `.github/` counts as code too. That is correct: a
  change to the filter should be measured by the pipeline it changes. Criterion 5 is ticked on
  structural evidence — `ci.yml` holds no patterns of its own — asserted by the `ci.yml reads the
  shared filter file` case in `tests/CoverageSliceSkip.Tests.ps1`. The empirical confirmation
  arrives on the next pull request that touches only tooling or documentation: the "Skip notice
  (every changed path excluded)" step should run there instead of being skipped.
