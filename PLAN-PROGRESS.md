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

**The Gate has not run.** The human asked to stop after the artifacts. Stage 6 stays open until
the five-step Gate is green; only then take the success edge to `7-document`.
