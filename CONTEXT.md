# AHKFlowApp

Where a user defines the text expansions and keyboard shortcuts they want on Windows, organizes them into profiles, and generates the AutoHotkey scripts that run them. The app authors scripts; it never runs them.

## Language

### Definitions

**Hotstring**:
A trigger the user types and what it expands into. The expansion is not always literal text — see Kind.
_Avoid_: abbreviation, snippet, expansion, shortcut

**Hotkey**:
A key plus any of Ctrl/Alt/Shift/Win that runs an action — sending keystrokes or launching a program.
_Avoid_: shortcut, binding, keybinding, accelerator

**Trigger**:
The characters a user types to fire a Hotstring. Hotkeys have no trigger — they have a key and modifiers.
_Avoid_: abbreviation, alias, shortcut

**Replacement**:
What a Hotstring produces when it fires. Its meaning depends on the Hotstring's Kind, so it is not always the literal text that lands in the window.
_Avoid_: expansion, output, body, value

**Kind**:
Which flavour of Hotstring a definition is — Text, DateTime, Macro, or Raw. Decides how that Hotstring's Replacement is read.
_Avoid_: type, mode

**Macro**:
A Kind whose Replacement is a sequence of literal text, key presses, and an optional cursor marker rather than one run of text.
_Avoid_: template, placeholder snippet

**Raw**:
A Kind whose Replacement is a complete AutoHotkey hotstring definition the user wrote by hand, kept verbatim. Its Trigger and options come from what the user wrote rather than being set separately.
_Avoid_: Script (a retired name for this Kind — see ADR-0002), custom, advanced

**Delivery**:
How a Hotstring's Replacement reaches the target window — typed keystroke by keystroke, or pasted through the clipboard.
_Avoid_: send mode, paste mode, method

**Window context**:
The restriction that limits a Hotstring to windows matching a given executable, window class, or title. A Hotstring without one fires in every window.
_Avoid_: scope, filter, condition

### Organizing

**Profile**:
A named set of hotstrings and hotkeys that generates exactly one Script (see ADR-0001).
_Avoid_: group, set, collection, workspace

**All-profiles**:
Said of a hotstring or hotkey that belongs to every Profile, including profiles created later, instead of being listed in particular ones.
_Avoid_: Any, global, shared

**Category**:
A user's label for finding and filtering hotstrings and hotkeys. Carries no meaning in a generated Script.
_Avoid_: tag, group, folder

**Owner**:
The signed-in user a hotstring, hotkey, profile, or category belongs to. Every one of them has exactly one, and nothing is shared between owners.
_Avoid_: user, account, tenant

**Script**:
The AutoHotkey file generated for one Profile, which the user downloads and runs themselves.
_Avoid_: file, output, generated script, ahk

### History

**Snapshot**:
The recorded state of one hotstring or hotkey as it was before a change.
_Avoid_: revision, backup, before-image, audit record

**Version**:
A Snapshot's number within one item's timeline. Numbers count up from the item's first change and are never reused, so the oldest Snapshot still kept is not necessarily number one.
_Avoid_: revision number, generation

**Revert**:
Returning a hotstring or hotkey that still exists to one of its earlier Versions.
_Avoid_: rollback, undo, restore

**Restore**:
Bringing back a deleted hotstring or hotkey. Distinct from Revert, which acts on an item that was never deleted.
_Avoid_: undelete, recover, revert

**Purge**:
Permanently discarding a deleted hotstring or hotkey, ending its timeline.
_Avoid_: hard delete, destroy, wipe

**Recycle Bin**:
Where deleted hotstrings and hotkeys wait to be Restored or Purged.
_Avoid_: trash, bin, archive
