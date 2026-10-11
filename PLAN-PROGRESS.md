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
- Task 2: `6d071bd`. Tests green: the missing-field API test went red, then green, and the
  opt-in guard passed both times. The Integration slice passed: Application 365, CLI 25, API 241,
  Infrastructure 26. Deferrals: none.
- Task 3: `3e553aa`. Tests green: the CLI tests showed the 11 planned failures, then passed 57 of
  57. The Fast slice passed in all five projects. The Integration slice passed: Application 365,
  CLI 30, API 241, Infrastructure 26. `dotnet format --verify-no-changes` exited 0. Deferrals:
  none.

## Final whole-branch review

One fresh reviewer read the whole branch: no Critical findings. Two fixes, each proved by a test
that failed first:

- `6bb4c0a`: the Clone test set the field to `false`, now the default, so it passed even with
  the copy removed from `Clone()`. It now uses `true`.
- `f1f07e7`: `--no-inside-word false` asked for the option on in the old CLI and silently got off
  in the new one. It now gets on, as spec decision 3 promises. Both flags together still exit 2.

Deferred minors, for the human to decide:

- No Fast-slice command test covers a Raw create with `--inside-word`, `--no-inside-word`, or
  both. Only the CLI integration theory does.
- `RawHotstringFlowTests.SwitchRawToTextViaDialog_KeepsTheVisibleOptionStates` now passes on the
  default alone. bUnit rows still cover the decomposition.
- Two comments are slightly off: `IHotstringsApiClient.cs` says the Raw path "sends no value",
  and `Hotstrings.razor` names only the older CLI as a source of `true` on Raw rows.

## Resolved: the plan's own citations

The plan and spec cite the tree before the change. After Task 3, 39 of those citations failed
tiers 1 and 2 of `check-citation-freshness.ps1`, which the pre-push hook runs on this branch's
plan. Plans repository commit `5593c54` freezes both files early, as backlog 160 did. The same
check then reported no problem. Stage 9 still confirms the freeze.
