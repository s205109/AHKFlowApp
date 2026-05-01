# 026 - Generate .ahk script per profile

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: API

## Summary

Generate a valid AutoHotkey `.ahk` script per profile. Output = `HeaderTemplate` + generated hotstrings + generated hotkeys + `FooterTemplate`. Includes any row that is in the profile's junction table OR has `AppliesToAllProfiles=true`.

## User story

As a user, I want one `.ahk` per profile that I can download and run locally, with the rules I've defined for that profile (or marked "Any") translated to valid AutoHotkey syntax.

## Acceptance criteria

- [ ] New `AhkScriptGenerator` service in the Application layer; pure, testable, no DB calls.
- [ ] Generation is profile-scoped: includes hotkeys/hotstrings where `(HotkeyProfile/HotstringProfile contains profileId) OR AppliesToAllProfiles=true`.
- [ ] Output structure: `{Profile.HeaderTemplate}\n; --- Hotstrings ---\n{hotstrings}\n; --- Hotkeys ---\n{hotkeys}\n{Profile.FooterTemplate}`.
- [ ] Hotkey translation: `^!+#` modifier prefix order = Ctrl, Alt, Shift, Win; line is `{modifiers}{Key}::{Action}, {Parameters}` (e.g. `^!a::Send, hello`).
- [ ] Hotstring translation: `:{options}:{Trigger}::{Replacement}` where `options = "*?"` if `IsTriggerInsideWord`, plus the ending-character option per `IsEndingCharacterRequired` (matches old project's syntax).
- [ ] Deterministic ordering: hotstrings ordered by `Trigger` ASC, hotkeys ordered by `Description` ASC.
- [ ] Unit tests on `AhkScriptGenerator` cover: empty profile (just header+footer), each modifier combo, both `HotkeyAction` values, both hotstring option flags, ordering, "Any" inclusion logic.
- [ ] Integration test: seed a profile + mixed hotkeys/hotstrings (some specific, some Any), generate script, assert exact expected text.

## Out of scope

- Runtime execution of AutoHotkey (intentionally excluded).
- Comments referencing source row IDs (could be added later for debugging).
- Linting / validating that the generated AHK is syntactically correct beyond what our generator emits.

## Notes / dependencies

- Depends on **022b, 024, 024b, 025**.
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 4).
