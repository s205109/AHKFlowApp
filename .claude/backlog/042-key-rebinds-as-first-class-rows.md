# 042 - Key rebinds as first-class rows

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

A key rebind makes one key act as another. A common example is making Caps Lock act as Ctrl, or as several modifiers at once. Today a rebind can only live in the profile header as hand-written text. This item records why that is, and what it would take to model rebinds properly.

**Deferred on purpose.** Item 043 ships rebinds as header snippets, which works with no code change. Do not pick this up until header snippets have been in use long enough to show that rows are actually wanted.

## User story

As an owner, I want a key rebind to be a row like my other shortcuts, so that it gets the same editing, history, and conflict checking as everything else.

## Background

Three separate gaps block a rebind row today.

**Prefix characters.** AutoHotkey uses a leading `*` to make a key fire whatever other modifiers are held, and `~` to let the original key press through as well. The emitter builds only the four modifier symbols and the automatic `$`, so neither prefix can be produced.

**Key-up.** A modifier rebind needs two halves — one when the key goes down, one when it comes up. The key registry accepts single key names only, so there is no way to name the second half.

**Multi-modifier destination.** A remap destination must be one key from the registry. Making one key act as three modifiers at once cannot be expressed.

## The harder problem

Fixing all three would make a rebind *storable*. It would not make it *understood*.

Once Caps Lock acts as several modifiers, every shortcut using those modifiers has a second way to be triggered. Nothing in the app would know that, so the known-shortcut conflict warnings would describe a keyboard the owner no longer has. Adding columns does not fix this. Something has to model the rebind as a change to the keyboard, not as another shortcut row.

That is why this item is written down rather than built. The columns are the cheap part and the wrong part.

## Acceptance criteria

Only if and when this is picked up:

- [ ] A rebind is modelled as its own concept, not as an action on a normal hotkey row
- [ ] The generator emits both halves of a modifier rebind from one row
- [ ] The known-shortcut catalog accounts for the rebind when it checks for conflicts
- [ ] A profile with no rebind behaves exactly as it does today

## Out of scope

- Storing rebinds as ordinary hotkey rows with new prefix columns. That is the approach this item rejects
- Rebinding mouse buttons. The key registry has no mouse entries yet

## Notes / dependencies

- Item 043 is the accepted answer for now. Revisit only when snippets prove insufficient
- Whoever picks this up should start from the conflict-warning problem, not from the emitter
