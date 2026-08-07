# 064 - Hotkey warnings ignore keys a profile template already uses

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI

## Summary

A Profile's header template can define hotkeys. The shipped `capslock-modifier-layer` header preset
writes `*CapsLock::` and `*CapsLock up::` straight into the header. An owner can also type a hotkey
into a header or footer by hand.

Nothing in the app compares those to the owner's Hotkey rows. A row on the same key then stops
working as written, and the app says nothing.

## User story

As an owner, I want to be told when a hotkey I am adding uses a key my profile template already
uses, so that I find out before the script runs rather than after.

## Background

Two different failures, both silent today.

**The row is eclipsed.** A row emits `CapsLock::`. The header writes `*CapsLock::`. AutoHotkey treats
these as entirely separate hotkeys, and the wildcard one eclipses the plain one. The row stops
behaving as written and nothing errors.

**The two land on the same hotkey name.** A `Remap` row emits `CapsLock::Ctrl`, which AutoHotkey
expands to exactly `*CapsLock::` plus `*CapsLock up::` — the same two names the preset writes by
hand.

The duplicate check that would normally catch this compares Owner, Key, the four modifier flags, and
window context across **rows** (`CreateHotkeyCommand.cs:47-60`). Template text is not a row, so it
is never compared.

This is the same class of gap as item 044, which shipped the warning for a `Remap` row's
destination. Item 043 shipped the preset that makes it easy to hit.

## Acceptance criteria

- [x] A row whose key is used by a header or footer template of a Profile the row belongs to shows a warning
- [x] The warning names the Profile and says which template used the key
- [x] Both places a row can be edited show it — the edit dialog and the grid's inline row
- [x] Changing a row's Profiles without changing its key updates the warning
- [x] A row with "apply to all profiles" is checked against every Profile's templates
- [x] A wildcard template hotkey warns for a row on the same key, whatever modifiers the row carries
- [x] A template hotkey that declares its own modifiers warns only for a row carrying exactly those
- [x] A template line carrying its own modifiers, such as `^!c::`, does not make every row with that key warn
- [x] A comment line and a custom combination in a template are not read as key uses
- [x] The warning names at most three Profiles and counts the rest
- [x] The warning never blocks saving
- [x] A row whose key no template uses behaves exactly as it does today

## Out of scope

- Blocking the save. The warning is advice, like every other shortcut warning
- Warning on the Profile page when a template is edited. That is the opposite direction and needs a query the page does not have
- Making composite key rebinds first-class rows. Item 042 covers that and stays deferred
- Reading `HeaderPresetInserter` markers. The check reads the template text, because inserted text becomes the owner's and may be edited or hand-written

## Notes / dependencies

- Design: `docs/superpowers/specs/2026-08-05-header-template-key-use-warning-design.md`
- Prototype proving the parser rules: deleted on merge; read it at commits `7f4dcf78` and `c36861bd`
- The notice belongs beside the existing ones in `ShortcutWarning.razor`, the way 044 added `DestinationTextFor`
- Both call sites already hold full `ProfileDto` objects, and `ProfileDto` already carries both templates — `HotkeyEditDialog.razor:271` and `Hotkeys.razor:303`. No new endpoint is needed
- `ShortcutWarning.razor:75` decides re-evaluation from `(Combination, Kind, RemapDest)`. Profile scope has to join it, or a Profile change is ignored
- `CONTEXT.md:92` bans conflict, clash, collision, and duplicate for this area. The house word is "uses"
- `docs/development/ahk-v2-syntax.md` documents none of `*`, `~`, or `up::` in prose. It needs extending as part of this work
- Filed as 053, renumbered to 058. Renumbered again to 064 on 2026-08-07, because two items shared 058. See backlog 061
