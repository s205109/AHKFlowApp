# 041 - Limit a hotkey to one application

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API

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

- [ ] `Hotkey` gains `ContextMatchType` and `ContextValue`, matching the `Hotstring` columns and their validation rules
- [ ] Both are optional, and both must be set or both left empty
- [ ] The generator wraps context-limited hotkeys in `#HotIf WinActive(...)` and closes the group with a bare `#HotIf`
- [ ] Hotkeys with no context still emit unwrapped, and a group left open never captures them
- [ ] The hotkey edit dialog offers the same three match types the hotstring dialog offers
- [ ] The hotkeys list shows which hotkeys are limited, and to what
- [ ] An EF Core migration adds the columns, and existing hotkeys keep firing everywhere

## Out of scope

- Matching more than one application per hotkey. One value only, exactly like hotstrings today. See item 042 notes
- Excluding an application ("everywhere except this one")
- Conditions that are not a window match, such as a key's toggle state

## Notes / dependencies

- Reuse the existing grouping in `AhkScriptGenerator`, do not add a second one. Hotstring groups and hotkey groups must not interleave, or a group left open will capture the wrong entries
- The one-value limit is a real cost. A combination meant for several related windows needs one hotkey row per window. Widening it to a list is a separate item, and hotstrings would need the same change to stay consistent
