# Progress — backlog 183, one line ending and a byte-order mark in a downloaded script

Plan: `docs/superpowers/plans/2026-10-16-download-line-endings-bom-plan-183.md`

One line per finished task, written after its deliverable commit: the task, the deliverable
commit, the tests state, and deferrals.

Execution: inline (`superpowers:executing-plans`), one session, progress update after each task.

- [x] Task 1 — the generator writes LF only. `521dc804`. `AhkScriptGeneratorTests` 97/97 pass; the
      separator test failed under the `ReplaceLineEndings` mutation, as planned. Deferrals: none.
