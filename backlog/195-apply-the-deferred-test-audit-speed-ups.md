# 195 - Apply the deferred test-audit speed-ups

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (test suites)
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

Backlog 188 audited ten PowerShell Suites and applied only the cheapest changes, within a limit
of about five hours of runs. This item applies or rejects the rest: 101 proposals worth about 172
seconds of Suite time, listed in `docs/development/test-audit-deferred.md`.

## User story

As a developer, I want the slowest PowerShell Suites to run faster without losing any check, so
that the Gate and CI finish sooner.

## Acceptance criteria

- [ ] Every row in `docs/development/test-audit-deferred.md` is marked applied or rejected, with
      a one-line reason for each rejection.
- [ ] `docs/development/cycle-time-record.md` holds the before and after median of every Suite
      this item changes, each Suite run alone, one warm-up plus three counted runs.
- [ ] Every applied MERGE or REMOVE names, in its commit body, the test that still catches the
      defect, or the behaviour that is gone.
- [ ] Every Suite this item changes passes in the Gate.

## Out of scope

- Auditing Suites that backlog 188 did not audit. Run the `test-audit` workflow for those, as
  `docs/development/test-audit-workflow.md` describes.
- `tests/WorktreeRemoveHook.Tests.ps1`, which backlog 068 owns.

## Notes / dependencies

- Depends on backlog 188, whose branch adds `docs/development/test-audit-deferred.md`,
  `docs/development/test-audit-workflow.md` and the audit record. Start after 188 merges.
- Batch 1 holds 80 SPEED UP and 6 REWORK rows, about 113 seconds. Two of them need a production
  refactor: the StageTransition 15-edge loop and the in-process GitHub Actions worker count.
- Batch 2 holds 13 SPEED UP rows and 2 MERGE rows that no refuter tested, about 59 seconds. Most
  need new fixture code: a template repository, `git fast-import` filler, or `GIT_COMMITTER_DATE`
  in place of a sleep.
- Batch 1 showed that an auditor's estimate can be far off: a seed cache saved 1.7 of an
  estimated 17 seconds. Time each change before you keep it.
- Spec: none — the audit record in `docs/development/cycle-time-record.md` is the source.
- Plan: none yet — written at Stage 3.
