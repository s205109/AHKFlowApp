# 127 - Decide the platform for the five invariant suites

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (CI workflows, test runner scripts)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Five suites run two times in each CI run. They run on Linux in the `repo-invariants` job, and
again on Windows in the `powershell-suites` job. Nobody decided that. Decide whether the Windows
run is needed, and write the reason down.

## User story

As a developer reading CI, I want each suite's platform to be a decision I can find, so that a
defect that only appears on Windows cannot pass unnoticed, and a second run that proves nothing
cannot cost time.

## Acceptance criteria

- [x] The item records which of `BacklogNumbering`, `BacklogPlanPointer`, `BacklogStaleOpen`,
      `CitationFreshness`, and `SkillParity` depend on the path separator, on letter case in
      paths, or on the line ending.
- [x] One place in the repository states which platform each suite runs on, and why.
- [x] `tests/powershell-suites.json` carries a `platform` field. It is an array of strings, and
      the only allowed values are `windows` and `linux`. A suite that runs on both carries both,
      as `["windows","linux"]`. The array is never empty, and a test fails an unknown value.
- [x] Every `platform` value is backed by a recorded run, not by a guess. The item records, for
      each value, the command, the operating system, the commit, the date, and the result — or
      names a CI run whose log shows the same.
- [x] Someone runs `scripts/run-powershell-suites.ps1` on Linux and records what happens. Any
      path or host defect it actually hits is fixed. No path is rewritten on suspicion alone.
- [x] A test proves the runner starts, reads the manifest, and selects suites on Linux.
- [x] `scripts/ci/check-repo-invariants.ps1` calls `scripts/run-powershell-suites.ps1` with a
      selection that resolves to exactly the manifest's `invariants` set. A bare call would
      select every suite in the `suites` job, which is not what that job is for.
- [x] A test fails when the invariant job would run any suite outside the manifest's
      `invariants` set, or would miss one inside it.
- [x] The five suites still run on Windows, or the item names the evidence that made that run
      unnecessary.

## Evidence

Every `platform` value in `tests/powershell-suites.json` comes from one of the runs below. No
value is a guess, and no path was rewritten.

### The runs

CI run **33991643161**, commit **a5f0b1ea**, branch `fix/wt-decide-the-platform-for-the-fiv-108d64e7`,
**2026-09-05**. One run carries all four sources.

| Job | Runner OS | Result | What it proves |
|---|---|---|---|
| `powershell-suites` | `windows-latest` | success | the `windows` value on every entry in the `suites` job |
| `repo-invariants` | `ubuntu-latest` | success | the `linux` value on the five invariant suites |
| `linux-suite-probe` (temporary, job 101374984038) | `ubuntu-latest` | 35 of 52 passed | the `linux` value on the 35 that passed |
| `codex-skills-hash-parity` | `ubuntu-latest` | success | the `linux` value on `CodexSkillsHashParity.Tests.ps1` |

Two local runs, **2026-09-05**, on the same working tree. The Linux one ran in Docker, image
`mcr.microsoft.com/powershell:latest`, repository mounted read-only at `/repo`.

| Command | OS | Result |
|---|---|---|
| `./scripts/run-powershell-suites.ps1 -Suite 'ProcessWorkflow.Tests.ps1'` | Linux (container) | passed; the runner started and printed its header |
| `./tests/SuiteRunnerLinux.Tests.ps1` | Linux (container) | 7 of 7 cases passed |
| `./tests/SuiteRunnerLinux.Tests.ps1` | Windows 11, pwsh 7.6.5 | 7 of 7 cases passed |
| `./tests/MeasureTestModes.Tests.ps1` | Linux (container), 2026-09-06 | 3 of 3 cases passed |

The first three are the evidence for `SuiteRunnerLinux.Tests.ps1`, which is new in this item and
so has no earlier CI run of its own. The fourth is the evidence for `MeasureTestModes.Tests.ps1` —
see the section below for why it needed its own run.

### The runner starts on Linux

The one open question was whether `. "$PSScriptRoot\progress.common.ps1"` loads on Linux, because
dot-sourcing is not a cmdlet and the slash-agnostic rule does not cover it. It loads. The probe
job read the manifest, chose 52 suites, and ran all of them. `tests/SuiteRunnerLinux.Tests.ps1`
now proves the same thing on every pull request.

**No path was rewritten.** Not one of the 17 failures below is a path or host defect in the
runner.

### One suite was measured after the probe

`MeasureTestModes.Tests.ps1` arrived on `main` from backlog 128 while this item was in review, so
the probe above ran before it existed. Its Windows evidence is the `powershell-suites` job, which
has passed it on every pull request since it landed. Its Linux evidence is the container run in
the table above, on **2026-09-06**: 3 of 3 cases passed. So it carries `["windows","linux"]`.

It was worth running rather than assuming either way. The suite builds a stub `dotnet` and puts it
on `PATH`, which looked like it would need Windows command discovery to resolve a `.ps1` by a bare
name. It does not.

### Why 17 suites carry `["windows"]` after failing on Linux

Each one fails on Linux because the suite itself reaches for something only Windows has. The cause
is in the suite, not in the runner, and fixing any of them is outside this item.

All 17 are listed. Each cause below is the message the probe's own log carries, not a guess.

| Cause | Suites |
|---|---|
| `cmd` is not on the path | `AgentWorktreeGuard`, `WorktreePlansSymlink`, `RunFrontend` |
| `Start-Process -WindowStyle` is not supported on this edition of PowerShell | `WorktreeLockHonored`, `WorktreeHolderProbe` |
| Windows Principal and `Win32_ProcessStartup` are Windows-only | `WorktreePlanGuard`, `WorktreeWatcherWindow` |
| `powershell.exe` is absent, so `Get-Command` returns nothing and reading `.Source` on it throws under `Set-StrictMode` | `PrePushHook` |
| a Linux filesystem is case-sensitive, and an open file handle does not stop another writer | `Progress` |
| the git hook file is not marked executable, so git skips it | `AgentPreCommitHook` |
| the `gh` lookup reports `gh-failed`, and the suite expects a different outcome | `WorktreeMergedCleanupSweep`, `WorktreeMergedCleanupEligibility` |
| the pull request's base is not found, so the code falls back to `origin/main` | `CoverageSliceSkip` |
| the worktree removal and sweep paths leave the worktree in place | `WorktreeRemoveHook`, `WorktreeSweepRemoteBase` |
| the expected value is a Windows path shape | `WatchTask` |
| the renderer is invoked through a Windows-shaped executable path | `WorkflowPdfGenerator` |

Two notes on the `Progress` row, because an earlier draft of this table got it wrong. The suite
also checks Windows PowerShell 5.1, and on Linux that check **skips** rather than fails — the log
says "Windows PowerShell 5.1 check skipped: powershell.exe is not available." Its two real
failures are "Timings wanted: a different case must not change the answer", because
`.ToUpperInvariant()` names a different file on a case-sensitive filesystem, and "Locked timings:
the failure must be reported as a warning, not swallowed", because holding a file open on Linux
does not stop the write the suite expects to fail.

Those last two rows are separate on purpose. The log names `gh-failed` for the two cleanup suites:
`WorktreeMergedCleanupSweep` expected `gh-missing` and got `gh-failed`, and
`WorktreeMergedCleanupEligibility` printed "GitHub lookup unavailable (gh-failed); deciding on
local history only". `CoverageSliceSkip`'s log names no `gh` message at all — it reports only "The
pull request base must win over origin/main. Got 'origin/main'." Whether `gh` is behind that too
is a guess, so the table does not make it.

Why `gh` failed at all was not investigated, because fixing these three suites is outside this
item. What matters here is only that no Linux run has passed them, so they carry `["windows"]`.

### What the five invariant suites depend on

The first acceptance criterion. This is a reading of the code, and the runs above confirm all five
pass on both platforms.

| Suite | Path separator | Letter case in paths | Line ending |
|---|---|---|---|
| `BacklogNumbering` | No. Every path is built with `Join-Path`. | No path is compared for case. | Yes, and it is handled. It asserts LF, and `.gitattributes` marks `*.md` as `text eol=lf`, so the assertion holds on both platforms. |
| `BacklogPlanPointer` | No. `Join-Path` throughout. | No. | No. It reads item text and assumes no CRLF. |
| `BacklogStaleOpen` | No. `Join-Path` throughout. | No. | No. It writes its fixtures with an explicit `` `n `` join. |
| `CitationFreshness` | Yes, and it is handled. It normalises `\` to `/` before comparing paths. | No. | No. It reads target files line by line, so either ending works. |
| `SkillParity` | Yes, and it is handled. It trims either separator when it cuts a relative path out of a full one. | Yes, and it is a latent hole. `-notcontains` ignores letter case on every platform, while a Linux filesystem does not, so two skill folders differing only in case would pass. That is a gap in the check, not a platform defect. A follow-up item is named below. | Yes. It compares file bytes. Both copies come from the same checkout and get the same `.gitattributes` treatment, so the bytes agree. |

### The two decisions

**The five suites keep running on Windows.** They carry `["windows","linux"]` and run in both
jobs. Three reasons. The second run costs about nothing: removing it saves 0 seconds at six or
more workers and about 28 seconds at four, because a parallel run ends when its slowest suite
ends. The two runs are not the same run: the Linux job was chosen for speed and never for platform
coverage, while Windows is where this repository's own product lives. And three of the five touch
a path separator, letter case, or file bytes directly, so neither run proves the other. What would
change this: a measurement showing the Windows run adds real minutes to the gate. Re-measure the
four-worker case after backlog 126's suite division lands.

**The runner gained `-Job`, and the CI script delegates to it.** `scripts/ci/check-repo-invariants.ps1`
held a second copy of the five suite names, and two lists drift. Passing five wildcards would have
written the same five names under a different syntax, so it removed nothing. `-Job invariants` also
fits the code that was already there: `Select-SuiteEntry` hard-coded the job name it filtered on,
so the parameter generalised one line rather than adding a mechanism.

### Follow-up items to file

Neither is in this item's scope.

1. `codex-skills-hash-parity` runs its suite directly, so the manifest's `codex-parity` job is read
   by nothing. Make it call the runner with `-Job codex-parity`.
2. `SkillParity` compares directory names case-insensitively, as the table above records.

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
- The second run was known and left alone to keep backlog 121 small. Its comment block said so:
  "This does not change scripts/run-powershell-suites.ps1; that job still runs every suite, now
  gated behind this one." So the second run was an accident, not a decision, which is why this
  item exists. That sentence records the file before this item rewrote it, so it carries no line
  citation. <!-- citation-check:ignore  the cited line is gone: this item replaced that comment block -->
  Read it in the branch point, `git show cf0b2c67:scripts/ci/check-repo-invariants.ps1`.
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
