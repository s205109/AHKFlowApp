# 141 - Coverage tooling filter misses the test results module

## Metadata

- **Epic**: Developer workflow
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

The `coverage-tooling` list in `.github/code-paths-filter.yml` names every script the local
coverage run loads. `scripts/test-results.common.ps1` is missing from it, so a change to that file
does not count as a code change and the Gate skips the coverage slice.

## User story

As a developer, I want a change to any script the coverage run loads to make the Gate run the
coverage slice, so that a defect in one of them cannot reach a pull request unnoticed.

## Background

The patterns above `coverage-tooling` exclude every `.ps1` file under `scripts/`
(`.github/code-paths-filter.yml:33`, "- '!scripts/*.ps1'"). The `coverage-tooling` key is the
exception list that pulls the coverage run's own scripts back in
(`.github/code-paths-filter.yml:57`, "coverage-tooling:"). Its comment said the list was the entry
points plus everything `run-coverage.ps1` dot-sources. The fix rewrote that comment, so the line
number moved from 47 to 55.

`scripts/test-fast.ps1` is one of those entry points, and it dot-sources
`scripts/test-results.common.ps1` (`scripts/test-fast.ps1:57`, "$PSScriptRoot\test-results.common.ps1").
That module is on no list, so editing it reads as a documentation change.

Backlog 123 added the progress module and backlog 128 added the test-results module, and neither
updated the filter. Backlog 124 added `scripts/progress.common.ps1` to the list, because its own
change made `run-coverage.ps1` load it. It left this one alone rather than widen its scope.

`tests/CoverageSliceSkip.Tests.ps1` pins the list in three places: a literal `$expected` array, a
count assertion, and a loop that checks `run-coverage.ps1` still mentions each dot-sourced file.
All three move together.

## Acceptance criteria

- [x] `.github/code-paths-filter.yml` lists `scripts/test-results.common.ps1` under
      `coverage-tooling`.
- [x] The `$expected` literal in `tests/CoverageSliceSkip.Tests.ps1` names the same set as the
      YAML file, and its count assertion agrees.
- [x] The comment above `coverage-tooling` describes the rule the list actually follows. Today it
      says the list is what `run-coverage.ps1` dot-sources, and the list also carries
      `test-fast.ps1` and what that script loads.
- [x] A branch whose only change is `scripts/test-results.common.ps1` reads as a code change, so
      the coverage slice runs. `tests/CoverageSliceSkip.Tests.ps1` covers it.

## Out of scope

- Any other entry the list may be missing. Check for them, and file what you find; do not fix
  them here without saying so.
- Any change to what the coverage run measures.

## Notes / dependencies

- Found while working backlog 124, on 2026-09-07. Raised there and kept out of that item on
  purpose, so 124 stayed one concern.
- Spec: none — the gap and its fix are both one line each.
- Plan: `docs/superpowers/plans/2026-09-07-coverage-tooling-filter-plan-141.md`
- Reclassified from `trivial` to `moderate` at Pickup on 2026-09-07. A filed backlog item is
  never `trivial` (`docs/development/workflow.md:825`, "**A filed backlog item is never `trivial`.**").
  The size of the change did not decide this; the rule did.
- Out of scope check, done on 2026-09-07: the two entry points hold eleven dot-source statements
  naming seven distinct modules, and none of those seven dot-sources anything further. Those
  seven plus the two entry points are the nine files the list must hold. Only
  `scripts/test-results.common.ps1` was missing, so there is nothing else to file.
  `scripts/run-powershell-suites.ps1` stays off the list: `test-fast.ps1` starts it as a child
  process in PowerShell mode, which is a different slice.
- The suite now derives the expected set by reading both entry points, so the list cannot go
  stale again the way it did for backlog 123 and backlog 128.
