# Progress — backlog 183, one line ending and a byte-order mark in a downloaded script

Plan: `docs/superpowers/plans/2026-10-16-download-line-endings-bom-plan-183.md`

One line per finished task, written after its deliverable commit: the task, the deliverable
commit, the tests state, and deferrals.

Execution: inline (`superpowers:executing-plans`), one session, progress update after each task.

- [x] Task 1 — the generator writes LF only. `521dc804`. `AhkScriptGeneratorTests` 97/97 pass; the
      separator test failed under the `ReplaceLineEndings` mutation, as planned. Deferrals: none.
- [x] Task 2 — every downloaded file starts with a byte-order mark. `d2b17400`.
      `AhkFileEncodingTests` 3/3 and `AHKFlowApp.API.Tests.Downloads` 18/18 pass, including
      `GET_preview_script_matches_download_body`. Deferrals: none.
- [x] Task 3 — the CLI, the browser, and the import dialog keep the bytes. `3639fb8d`, tests only.
      `DownloadCliIntegrationTests` 10/10, `HotstringImportDialogTests` 10/10, E2E suite 93/93
      pass; the import test failed under its reader mutation, as planned. The tests were committed
      before the E2E run, because PowerShell needs the exit and re-enter cycle. Deferrals: none.

## Simplify

Four review angles ran: reuse, simplification, efficiency, altitude. Applied:

- Deleted `GetBytes_Script_StartsWithTheByteOrderMark`. `GetBytes_NonAsciiText_WritesUtf8AfterTheMark`
  already checks the mark, ASCII, and non-ASCII with literal bytes. So Task 2 now has two unit
  tests, not the three the plan names.
- Removed the caller list from the `AhkFileEncoding` summary, because it would go stale.
- Corrected the preview comments in `GetHotstringPreviewQuery` and `GetHotkeyPreviewQuery`. They
  said the preview matches the download byte for byte. After this branch only the line endings
  can differ.

Skipped:

- One shared LF helper for the seven `Replace("\r\n", "\n").Replace('\r', '\n')` sites. It touches
  five files outside this branch and a frontend copy. A candidate for its own item.
- An LF paste helper in the edit-dialog previews. The plan keeps those snippets out of scope (D5).

## Verify

Verification artifacts, run on `a09e7e01` on 2026-10-16, all green:

- `test-fast.ps1 -Mode Fast`: emitted `.ahk` text and the BOM unit tests. Application 1791,
  UI.Blazor 1041, CLI 197, Domain 44, TestUtilities 14.
- `test-fast.ps1 -Mode Integration`: the API download tests and the CLI download flows.
  Application 386, CLI 30, API 254, Infrastructure 27.
- `test-fast.ps1 -Mode E2E`: `ProfileScriptDownloadFlowTests` saves a real download and checks
  its bytes. 93 of 93.
- Diff review: worktree clean, `git diff --check origin/main...HEAD` clean, no package change.

No manual steps. The change emits no new AHK construct, so the text assertions are the contract.

### Gate

Run on 2026-10-16. All five steps are green on `7e3aabc4`.

1. `dotnet build AHKFlowApp.slnx --configuration Release`: 0 errors.
2. `dotnet format AHKFlowApp.slnx --verify-no-changes`: exit 0.
3. `test-fast.ps1 -Mode PowerShell`: green after one fix and one rerun.
   - Run 1 failed `CitationFreshness.Tests.ps1`. This branch had moved lines that four Document-time
     citations in `backlog/done/160-one-home-for-emitted-runtime-helpers.md` point at, and one
     citation in the 183 plan. Fixed in `7e3aabc4` (item 160 frozen with `citation-check:ignore`)
     and plans-repo `78679fb` (plan line number updated).
   - Run 2 passed 76 of 77 suites, `CitationFreshness.Tests.ps1` included. It failed
     `MeasureTestModes.Tests.ps1`, "A slow head is discarded and the median is the flat tail": a
     median of 0.68 s against a 0.5 s threshold. That test times a stub process, so it is
     sensitive to machine load. It passed in run 1 and again alone on `7e3aabc4`. This branch
     does not touch the script or the suite.
4. `test-fast.ps1 -Mode Coverage`: every test passed, and every per-assembly threshold was met.
5. `git diff --check origin/main...HEAD`: clean, rerun after the fix.

Verdict: verification artifacts green, Gate green, no manual steps. Success edge to `7-document`.

## Review round 1

One P2 thread on PR #444: the acceptance evidence cited two API test methods at lines 185 and
205. CI checks the merge result with `main`, where backlog 184 moved them to 208 and 228. Verdict
CONFIRMED. No code change.

- Merged `main` at `b7a1953b` into the branch (`4616008b`), then updated the two line numbers
  (`2a150a96`). The plan's citation of `GenerateAllProfileScriptsQuery.cs` moved too, from line 55
  to 57 (plans-repo `2e2c2ad`). The citation check passes on the repository and on the plan.
- The Gate on the merged branch is green:
  - Build, format, and `diff --check` passed.
  - The PowerShell suites passed 76 of 77. `CiPowerShellSuiteRunner.Tests.ps1` failed on a
    Windows file lock in a temporary folder ("being used by another process"), then passed alone.
  - The first Coverage run failed: the Docker engine restarted during it. Every SQL container on
    the machine exited with code 255 at the same moment. A rerun failed one E2E test on a
    first-page-load timeout, `HotkeysMobileFlowTests.PhoneViewport_MarkedRowWithTheLongestCombo_KeepsTheTriggerCellInsideItsColumn`.
    The second rerun was clean, and every per-assembly threshold was met.
