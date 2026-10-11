# Progress — backlog 163, new hotstrings start with Trigger inside words off

Plan: `docs/superpowers/plans/2026-10-11-new-hotstring-inside-word-default-plan-163.md`

Base revision: `9672d6e`.

One line per finished task, written after its deliverable commit.

## Tasks

- Task 1: `25a867b`. Tests green: the four new UI tests went red, then green. The UI test
  project passed 1001 of 1001. The E2E slice went red on the three planned flows, then passed 80
  of 80. Deferrals: none. One change the plan did not list:
  `ClipboardDeliveryFlowTests.AutoLongText_DownloadedScriptContainsOneHelperAndPasteCall` read
  `:X?:longclip::` from the old default, and now reads `:X:longclip::`.
