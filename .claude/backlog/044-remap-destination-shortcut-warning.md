# 044 - Known-shortcut warnings ignore a remap destination

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI

## Summary

The shortcut warning looks at the key a hotkey is bound to. It never looks at where a `Remap` row sends that key. So a remap that changes what a whole set of shortcuts does raises no warning at all.

## User story

As an owner, I want to be warned when a remap changes what my other shortcuts do, so that I find out before the script runs rather than after.

## Background

`KnownShortcutWarning.Match` compares one row's key and four modifier flags against the catalog. That covers the source side correctly. Remapping F1 warns, because F1 is in the catalog.

The destination side is not covered. Remapping Caps Lock to Ctrl means every Ctrl shortcut in the catalog gains a second way to fire, from a key that used to do something else. Remapping a key to `Volume_Mute` means the media key now has two sources. Nothing checks either.

This is the small version of the problem item 042 describes. Item 042 defers the composite rebind that makes the problem large. This item covers the rows that already ship, so it does not depend on 042 and should not wait for it.

## Acceptance criteria

- [ ] A `Remap` row whose destination is a modifier key warns that shortcuts using that modifier gain a second trigger
- [ ] A `Remap` row whose destination matches a known shortcut warns, naming what already uses it
- [ ] The warning says which side of the remap it is about, so a row that warns on both sides is not confusing
- [ ] A row that is not a `Remap` behaves exactly as it does today
- [ ] The check runs in the edit dialog, on the same catalog fetch the existing warning uses, with no extra request

## Out of scope

- Composite rebinds and multi-modifier destinations. Item 042 covers those
- Blocking the save. The warning is advice, like every other shortcut warning
- Following a chain of remaps, where one row's destination is another row's source

## Notes / dependencies

- The matcher lives in `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/KnownShortcutWarning.cs`
- The warning text is composed from a shortcut's uses, never switched on one value. Keep that shape — see the remarks on `KnownShortcutWarning`
- Item 038 puts the same warning on the list page. If 038 lands first, this check must reach both places
