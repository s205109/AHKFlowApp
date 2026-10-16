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
