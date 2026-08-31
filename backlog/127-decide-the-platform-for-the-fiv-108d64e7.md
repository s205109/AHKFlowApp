# 127 - Decide the platform for the five invariant suites

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (CI workflows, test runner scripts)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

Five suites run two times in each CI run. They run on Linux in the `repo-invariants` job, and
again on Windows in the `powershell-suites` job. Nobody decided that. Decide whether the Windows
run is needed, and write the reason down.

## User story

As a developer reading CI, I want each suite's platform to be a decision I can find, so that a
defect that only appears on Windows cannot pass unnoticed, and a second run that proves nothing
cannot cost time.

## Acceptance criteria

- [ ] The item records which of `BacklogNumbering`, `BacklogPlanPointer`, `BacklogStaleOpen`,
      `CitationFreshness`, and `SkillParity` depend on the path separator, on letter case in
      paths, or on the line ending.
- [ ] One place in the repository states which platform each suite runs on, and why.
- [ ] `tests/powershell-suites.json` carries a `platform` field. Every value comes from a run,
      not from a guess.
- [ ] `scripts/run-powershell-suites.ps1` and `scripts/progress.common.ps1` build every path
      with `Join-Path` or a forward slash.
- [ ] A test proves the runner starts and selects suites on Linux.
- [ ] `scripts/ci/check-repo-invariants.ps1` calls `scripts/run-powershell-suites.ps1`, so the
      repository holds one parallel implementation and not two.
- [ ] The five suites still run on Windows, or the item names the evidence that made that run
      unnecessary.

## Out of scope

- Everything in backlog 126.
- Changing which suites the `repo-invariants` job runs.
- Removing the `repo-invariants` job, or moving it to Windows.

## Notes / dependencies

- Spec: none — the grilling round for backlog 126 produced this question, and this item answers
  it.
- The Linux job was chosen for speed, not for platform coverage
  (`backlog/done/121-backlog-numbering-reads-one-working-tree.md:38`, "- [x] That job finishes in under two minutes on a normal pull request. Confirmed: the first `repo-invariants` run on pull request #360 took 1 minute 14 seconds. The local Windows run was 2 minutes 4 seconds, so Linux process startup is indeed faster.").
- The second run was known and left alone to keep that item small
  (`scripts/ci/check-repo-invariants.ps1:16`, "    scripts/run-powershell-suites.ps1; that job still runs every suite, now gated behind this one.").
  So the second run is an accident, not a decision, which is why this item exists.
- Removing the Windows run saves 0 seconds at six or more workers, and about 28 seconds at
  four. A parallel run ends when the slowest suite ends, not when the work is done, so removing
  work from the pool changes nothing until the pool is thin.
- Backlog 126 divides the slowest suite. After it ships, re-measure the four-worker case before
  using the numbers above.
- `scripts/progress.common.ps1` declares `#Requires -Version 5.1`, and `scripts/test-fast.ps1`
  dot-sources it and declares the same. A path fix there must stay inside 5.1.
- Backlog 126 leaves `scripts/ci/check-repo-invariants.ps1` alone for this reason: the runner
  cannot start on Linux today, and that job runs on Linux.
