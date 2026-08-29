# 124 - Coverage runner prints progress and an estimate

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

`scripts/run-coverage.ps1` prints nothing that says how far along it is. It reuses the progress
module that item 123 adds, so a coverage run reports its position and an estimated time left.

## User story

As a developer, I want a coverage run to say which phase it is in and how much time is left, so
that I can tell a slow run from a stuck one.

## Background

Item 123 builds `scripts/progress.common.ps1` and wires it into
`scripts/run-powershell-suites.ps1` and `scripts/test-fast.ps1`. Those two runners have one
simple unit shape each: a suite file, and a test project.

`scripts/run-coverage.ps1` is different. Its units are not all the same kind. It runs a restore,
then a build, then a loop over the coverage projects, then reportgenerator. A mixed list of
phases and projects is a third unit shape, and it was kept out of item 123 on purpose, so the
shared module could prove itself against two shapes before it took on a third.

## Acceptance criteria

- [ ] `scripts/run-coverage.ps1` prints a progress line before each of its units through
      `scripts/progress.common.ps1`.
- [ ] Its unit list names the restore, the build, each coverage project, and the report step.
- [ ] Its remembered timings live under their own runner key, so they never mix with the keys
      that `scripts/test-fast.ps1` writes.
- [ ] A coverage run started through `scripts/test-fast.ps1 -Mode Coverage` prints one progress
      sequence, not two nested ones.
- [ ] `tests/Progress.Tests.ps1`, or a suite beside it, covers a unit list that mixes fixed
      phase names with a project list read at run time.

## Out of scope

- Any change to what `scripts/run-coverage.ps1` measures or reports about coverage itself.
- Any change to the progress module's public functions. If this item needs one, that is a signal
  the module's shape is wrong, and the change belongs in a revision of item 123's design.

## Notes / dependencies

- Blocked until item 123 ships, because the module it uses does not exist yet.
- Spec: none — this item reuses the design written for item 123.
- Plan: none — filed at intake. A plan is written when somebody picks the item up.
