# 041 - Limit a hotkey to one application

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API
- **Stage**: 9-ship

## Summary

A hotstring can be limited to one application, but a hotkey cannot. Every hotkey fires everywhere. Someone who wants `Ctrl+Shift+E` to do one thing in a text editor and nothing elsewhere has no way to say so.

## User story

As an owner, I want to limit a hotkey to one application, so that a key combination can mean different things in different programs.

## Background

`Hotstring` already carries `ContextMatchType` and `ContextValue`, and `AhkScriptGenerator` groups hotstrings by that pair and wraps each group in `#HotIf WinActive(...)`. `Hotkey` has neither column. This item copies the hotstring model onto hotkeys and reuses the same grouping, so the two entities stay consistent.

Example of the intended output:

```ahk
#HotIf WinActive("ahk_exe notepad.exe")
^+e::Run("https://example.com")
#HotIf
```

## Acceptance criteria

- [x] `Hotkey` gains `ContextMatchType` and `ContextValue`, matching the `Hotstring` columns and their validation rules
- [x] Both are optional, and both must be set or both left empty
- [x] The generator wraps context-limited hotkeys in `#HotIf WinActive(...)` and closes the group with a bare `#HotIf`
- [x] Hotkeys with no context still emit unwrapped, and a group left open never captures them
- [x] The hotkey edit dialog offers the same three match types the hotstring dialog offers
- [x] The hotkeys list shows which hotkeys are limited, and to what
- [x] An EF Core migration adds the columns, and existing hotkeys keep firing everywhere

### Uniqueness

Context changes what counts as a duplicate. Today one key plus modifier combination may exist once per owner, whatever the context.

- [x] Uniqueness covers owner, key, all four modifiers, and the context pair together
- [x] The same key and modifier combination is allowed in two different contexts
- [x] The same key and modifier combination in the same context is still a conflict
- [x] Two hotkeys with no context are still a conflict, so an owner keeps one global row per combination
- [x] The migration replaces the `IX_Hotkey_Owner_Modifiers` unique index with one that includes both context columns
- [x] The new index sets `.HasFilter(null)`, the same way `IX_Hotstring_Owner_Trigger_Context` does, so SQL Server treats two all-null context rows as duplicates
- [x] The conflict message names the context, so an owner can tell a global clash from a per-application one

### History

`HotkeySnapshot` carries every editable field, and restore and revert rebuild the hotkey from it. A snapshot that skips context would turn a limited hotkey back into a global one.

- [x] `HotkeySnapshot` carries `ContextMatchType` and `ContextValue`
- [x] Both are optional and default to null, so a snapshot written before this change restores as a global hotkey — the same pattern `HotstringSnapshot` already uses
- [x] Restore and revert put the captured context back, and a restored hotkey that clashes with a live one still returns a conflict

## Out of scope

- Matching more than one application per hotkey. One value only, exactly like hotstrings today. The cost is spelled out under Notes below
- Excluding an application ("everywhere except this one")
- Conditions that are not a window match, such as a key's toggle state

## Notes / dependencies

- Reuse the existing grouping in `AhkScriptGenerator`, do not add a second one. Hotstring groups and hotkey groups must not interleave, or a group left open will capture the wrong entries
- The one-value limit is a real cost. A combination meant for several related windows needs one hotkey row per window. Widening it to a list is a separate item, and hotstrings would need the same change to stay consistent
