# 059 - LControl and RControl are not accepted key spellings

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: API, UI, CLI

## Summary

AutoHotkey names the side-specific control keys `LControl` and `RControl` as well as `LCtrl` and
`RCtrl`. The alias map in `HotkeyKeys.cs:109-123` holds `Control` → `Ctrl`, but neither side form.

So `LControl` is rejected as a hotkey key, and it does not canonicalize to `LCtrl`. A Profile
template that writes `*LControl::` shows no warning for a row on `LCtrl`, because the two names
never meet.

## Background

Found while addressing review findings on item 058. The one-line alias addition was reverted,
because it breaks a frozen invariant rather than the feature under review.

`LegacyHotkeyFixtures.cs:161` builds its Send-token fixtures from `HotkeyKeys.Aliases` at run time.
`HotkeyTypedActionsMigrationTests` then asserts that the applied migration
`20260722105522_HotkeyTypedActions.cs:110` classifies each fixture exactly as the C# converter
does. That migration carries a hard-coded name list which cannot gain a new alias after the fact:
rows were already backfilled with the classification it made at the time.

So adding any alias whose canonical key carries the `SendToken` role fails that test today.

## Acceptance criteria

- [x] `LControl` canonicalizes to `LCtrl`, and `RControl` to `RCtrl`
- [x] Both spellings are accepted at the create and update boundaries
- [x] A template line `*LControl::` warns for a row on `LCtrl`
- [x] The migration parity test still passes, and the reason it passes is written down

## Out of scope

- Editing the applied migration's SQL. Rows are already backfilled with what it decided

## Notes / dependencies

- Official key names: https://www.autohotkey.com/docs/v2/KeyList.htm
- Decide first how the fixture set should treat aliases added after a migration shipped. Either the
  fixtures snapshot the alias list that migration knew, or the parity test excludes later aliases
- Same question applies to every future alias, not only these two
- Answered by: `docs/superpowers/specs/2026-08-07-lcontrol-rcontrol-aliases-design.md`. The fixture
  set becomes an additions allow-list — `LegacyHotkeyFixtures.s_spellingsAddedAfterMigrationA` names
  later spellings and skips them. Both sides of the resulting split are pinned by tests. ADR 0004
  carries the reason under "Adding a key spelling after Migration A"
