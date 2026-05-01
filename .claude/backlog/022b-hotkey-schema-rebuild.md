# 022b - Hotkey schema rebuild

## Metadata

- **Epic**: Hotkeys
- **Type**: Refactor
- **Interfaces**: API

## Summary

Rebuild the `Hotkey` domain entity and its API surface to match the AHKFlow reference model. Replaces the free-form `Trigger`/`Action`/`Description` shape from the original 021/022 implementation.

## User story

As a developer, I want the `Hotkey` schema and API to use structured fields (Description, Key, modifier flags, Action enum, Parameters) so the UI can render the screenshot layout and the script generator can emit AutoHotkey syntax directly.

## Acceptance criteria

- [ ] `Hotkey` entity has fields: `Description` (≤200, required), `Key` (≤20, required), `Ctrl`, `Alt`, `Shift`, `Win` (bools), `Action` (HotkeyAction enum), `Parameters` (≤4000), `AppliesToAllProfiles` (bool), plus `Id`, `OwnerOid`, timestamps.
- [ ] New `HotkeyAction` enum in Domain: `Send=0, Run=1` (extensible).
- [ ] EF migration drops the old `Trigger`/`Action`/`Description` string columns and the nullable `ProfileId`; adds the new fields. Dev DBs are scratch (per spec D7); no copy-forward SQL.
- [ ] Unique index on `(OwnerOid, Key, Ctrl, Alt, Shift, Win)`.
- [ ] API DTOs (`HotkeyDto`, `Create`, `Update`) reflect the new shape; controller + handlers + FluentValidation rebuilt.
- [ ] Existing 021 + 022 tests are deleted/rewritten; new unit + integration tests cover the rebuilt API.

## Out of scope

- Many-to-many profile association (covered in 024b).
- UI changes (covered in 022).
- Adding new `HotkeyAction` enum values beyond `Send` and `Run`.

## Notes / dependencies

- Supersedes 021 in practice. 021 stays in the backlog as a historical record.
- Depends on **024 + 024b** for profile association (`AppliesToAllProfiles` flag pairs with the `HotkeyProfile` junction).
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 3).
