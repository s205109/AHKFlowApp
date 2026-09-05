# 127 - Decide the platform for the five invariant suites

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (CI workflows, test runner scripts)
- **Difficulty**: moderate
- **Stage**: 3-plan

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
- [ ] `tests/powershell-suites.json` carries a `platform` field. It is an array of strings, and
      the only allowed values are `windows` and `linux`. A suite that runs on both carries both,
      as `["windows","linux"]`. The array is never empty, and a test fails an unknown value.
- [ ] Every `platform` value is backed by a recorded run, not by a guess. The item records, for
      each value, the command, the operating system, the commit, the date, and the result — or
      names a CI run whose log shows the same.
- [ ] Someone runs `scripts/run-powershell-suites.ps1` on Linux and records what happens. Any
      path or host defect it actually hits is fixed. No path is rewritten on suspicion alone.
- [ ] A test proves the runner starts, reads the manifest, and selects suites on Linux.
- [ ] `scripts/ci/check-repo-invariants.ps1` calls `scripts/run-powershell-suites.ps1` with a
      selection that resolves to exactly the manifest's `invariants` set. A bare call would
      select every suite in the `suites` job, which is not what that job is for.
- [ ] A test fails when the invariant job would run any suite outside the manifest's
      `invariants` set, or would miss one inside it.
- [ ] The five suites still run on Windows, or the item names the evidence that made that run
      unnecessary.

## Out of scope

- Everything in backlog 126.
- Changing which suites the `repo-invariants` job runs.
- Removing the `repo-invariants` job, or moving it to Windows.

## Notes / dependencies

- Spec: none — the grilling round for backlog 126 produced this question, and this item answers
  it.
- Plan: `docs/superpowers/plans/2026-09-05-invariant-suite-platform-plan-127.md`
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
  dot-sources it and declares the same. Any fix there must stay inside 5.1.
- Backlog 126 leaves `scripts/ci/check-repo-invariants.ps1` alone because that job runs on
  Linux and nobody has run the runner there. That is an unknown, not a known defect.
- An earlier draft of 126 claimed two backslash paths stop the runner from starting on Linux.
  The claim was wrong, and it is withdrawn. Microsoft documents that "Paths given to cmdlets are
  now slash-agnostic (both `/` and `\` work as directory separators)". See
  [PowerShell differences on non-Windows platforms](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support?view=powershell-7.6#filesystem-support-for-linux-and-macos).
  Start this item by running the thing, not by rewriting paths.
- Dot-sourcing is not a cmdlet, so the documented rule above does not settle
  `. "$PSScriptRoot\progress.common.ps1"` by itself. That is one more reason to run it and
  read the result rather than reason about it.
- Backlog 126 gives the runner one selection argument, `-Suite <wildcard[]>`, and it matches only
  suites inside the `suites` job. That cannot express "exactly the `invariants` set" without
  naming all five suites again, which is the duplication the manifest exists to remove. So this
  item most likely adds a second selector, `-Job invariants`, rather than passing five wildcards.
  Decide that when you pick the item up, and write the reason down either way.
- The manifest 126 ships has four fields: `name`, `jobs`, `execution`, and `baselineSeconds`, plus
  `reason` on an `exclusive` entry. The `platform` field this item requires is new work, and the
  manifest reader must learn to validate it. Its plan is
  `docs/superpowers/plans/2026-08-31-powershell-suite-performance-plan-126.md`.
