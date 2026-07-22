# AHKFlowApp

Where a user defines the text expansions and keyboard shortcuts they want on Windows, organizes them into profiles, and generates the AutoHotkey scripts that run them. The app authors scripts; it never runs them.

## Language

### Definitions

**Hotstring**:
An AutoHotkey rule that fires when typed characters match its Trigger. Its Kind decides what firing does — inserting text, a formatted date or time, a Macro sequence, or whatever a Raw definition says.
_Avoid_: abbreviation, snippet, expansion, shortcut

**Hotkey**:
A key plus any of Ctrl/Alt/Shift/Win that runs one Action.
_Avoid_: shortcut, binding, keybinding, accelerator

**Trigger**:
The characters a user types to fire a Hotstring. Hotkeys have no trigger — they have a key and modifiers.
_Avoid_: abbreviation, alias, shortcut

**Replacement**:
The Kind-specific content of a Hotstring: literal text for Text, a token sequence for Macro, the entire normalized definition for Raw. Date & time hotstrings have no Replacement — they carry a format and optional offset instead.
_Avoid_: expansion, output, body, value

**Kind**:
Which flavour of Hotstring a definition is — Text, Date & time, Macro, or Raw. Decides how that Hotstring's Replacement is read.
_Avoid_: type, mode

**Action**:
What a Hotkey does when it fires — one of SendText, SendKeys, Run, Window, Remap, Disable, or Raw. Decides which fields that Hotkey carries and how its line is generated; it is to a Hotkey what Kind is to a Hotstring.
_Avoid_: type, command, operation

**Macro**:
A Kind whose Replacement is a sequence of literal text, Enter and Tab key presses, and an optional cursor marker rather than one run of text.
_Avoid_: template, placeholder snippet

**Raw**:
A Kind holding one complete AutoHotkey hotstring definition instead of structured fields. The app normalizes its layout, lifts leading comments into the description, and derives its Trigger and options from the definition text, which stays the single source of truth (see ADR-0002).
Also an Action, holding a verbatim body a Hotkey runs instead of structured fields. Only its shape is checked; the app writes it into the Profile script unchanged, so a mistake in one can stop the whole script from loading (see ADR-0004).
_Avoid_: Script (a retired name for this Kind), custom, advanced

**Remap**:
The Action that makes a Hotkey's key behave as another key. It names one destination key and nothing else — no modifiers, no further action.
_Avoid_: rebind, swap, alias

**Run target**:
The application, URL, or folder a Run Action launches. It is a command line rather than a path, so arguments are allowed; which of the three it is labelled as only changes how the app presents it, never what is generated.
_Avoid_: path, executable, program

**Delivery**:
How a Text Hotstring's Replacement reaches the target window — typed keystroke by keystroke, or pasted through the clipboard. Auto picks between the two by Replacement length.
_Avoid_: send mode, paste mode, method, Hotstring (the current UI label for typed delivery)

**Window context**:
The restriction that limits a Hotstring to windows matching a given executable, window class, or title substring. A Hotstring without one fires in every window.
_Avoid_: scope, filter, condition

**Options**:
The settings that shape how a Hotstring fires: case sensitivity, triggering inside words, and Ending character behavior. Structured Kinds expose them as individual toggles; a Raw definition carries them as flag letters inside the definition text, from which they are derived.
_Avoid_: flags (for the toggles), settings, modifiers

**Ending character**:
The character — a space, period, enter, or similar — typed after a Trigger to fire its Hotstring. A Hotstring can waive it (firing the moment the Trigger completes) or omit it from what the Replacement produces; omitting is meaningful only when one is required.
_Avoid_: terminator, delimiter, end char

**Description**:
A user's note on a hotstring or hotkey, carried into its Profile script as a comment above the definition. For a Raw Hotstring it is lifted from the leading comments of the pasted definition.
_Avoid_: comment, note, label

### Organizing

**Profile**:
A named set of hotstrings and hotkeys that generates exactly one Profile script (see ADR-0001).
_Avoid_: group, set, collection, workspace

**Apply to all profiles**:
Said of a hotstring or hotkey that belongs to every Profile, including profiles created later, instead of being listed in particular ones.
_Avoid_: Any, global, shared, all-profiles

**Category**:
A user's label for finding and filtering hotstrings and hotkeys; a default set is seeded for each new Owner. Carries no meaning in a generated Profile script.
_Avoid_: tag, group, folder

**Owner**:
The signed-in user a hotstring, hotkey, profile, or category belongs to. Every one of them has exactly one, and nothing is shared between owners.
_Avoid_: user, account, tenant

**Profile script**:
The complete AutoHotkey file generated for one Profile — header, footer, and every definition that applies — which the user downloads and runs themselves.
_Avoid_: script (unqualified), file, output, ahk

**Header/Footer template**:
The user-editable text a Profile places before and after the definitions in its Profile script. Tokens such as the profile's name or the generation time are substituted when the script is generated; unknown tokens are left as typed.
_Avoid_: preamble, banner, boilerplate, prologue/epilogue

### History

**Snapshot**:
A recorded state in one item's history. Edit and Delete Snapshots capture the state being replaced; a Restore Snapshot captures the state brought back.
_Avoid_: revision, backup, before-image, audit record

**Version**:
A Snapshot's number within one item's timeline. Numbers count up from the item's first change and are never reused, so the oldest Snapshot still kept is not necessarily number one.
_Avoid_: revision number, generation

**Tombstone**:
The Delete Snapshot that preserves a deleted item's last state; the Recycle Bin reads from it.
_Avoid_: soft delete, deletion marker

**Revert**:
Returning a hotstring or hotkey that still exists to one of its earlier Versions.
_Avoid_: rollback, undo, restore

**Restore**:
Bringing back a deleted hotstring or hotkey. Distinct from Revert, which acts on an item that was never deleted.
_Avoid_: undelete, recover, revert

**Purge**:
Permanently discarding every Snapshot of a deleted hotstring or hotkey, making recovery impossible.
_Avoid_: hard delete, destroy, wipe

**Recycle Bin**:
Where deleted hotstrings and hotkeys wait to be Restored or Purged.
_Avoid_: trash, bin, archive
