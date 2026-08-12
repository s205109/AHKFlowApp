# 042 - Composite key rebinds as first-class rows

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API
- **Status**: Deferred
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

A key rebind makes one key act as another.

A **simple** rebind is already a first-class row. The `Remap` action kind takes one registry key as the source and one as the destination, and the emitter writes `CapsLock::Ctrl` from it. That path ships today and this item does not change it.

A **composite** rebind is the gap. Making Caps Lock act as several modifiers at once, letting the original key press through as well, or firing whatever other modifiers are held — none of those can be stored. Today they can only live in the profile header as hand-written text. This item records why, and what it would take to model them properly.

**Deferred on purpose.** Item 043 ships composite rebinds as header snippets, which works with no code change. Do not pick this up until header snippets have been in use long enough to show that rows are actually wanted.

## User story

As an owner, I want a composite key rebind to be a row like my other shortcuts, so that it gets the same editing, history, and conflict checking as everything else.

## Background

Three separate gaps block a composite rebind row today. None of them blocks the simple `Remap` row that already ships.

**Prefix characters.** AutoHotkey uses a leading `*` to make a key fire whatever other modifiers are held, and `~` to let the original key press through as well. The emitter builds only the four modifier symbols and the automatic `$`, so neither prefix can be produced.

**Key-up.** A modifier rebind needs two halves — one when the key goes down, one when it comes up. The key registry accepts single key names only, so there is no way to name the second half.

**Multi-modifier destination.** A remap destination must be one key from the registry. Making one key act as three modifiers at once cannot be expressed.

## The harder problem

Fixing all three would make a composite rebind *storable*. It would not make it *understood*.

Once Caps Lock acts as several modifiers, every shortcut using those modifiers has a second way to be triggered. Nothing in the app would know that, so the known-shortcut conflict warnings would describe a keyboard the owner no longer has. Adding columns does not fix this. Something has to model the rebind as a change to the keyboard, not as another shortcut row.

That is why this item is written down rather than built. The columns are the cheap part and the wrong part.

**This blindness is not only a future problem.** A simple `Remap` row already causes it, and those ship today. The warning matches a row's own key and modifiers against the catalog, so it does warn about the key being remapped away. It knows nothing about the destination. An owner who remaps Caps Lock to Ctrl has given every Ctrl shortcut in the catalog a second way to fire, and nothing in the app accounts for that. That is an existing correctness gap, not a deferred one, so it is tracked on its own as item 044. Do not wait for this item to fix it.

## Acceptance criteria

Only if and when this is picked up:

- [ ] A composite rebind is modelled as its own concept, not as an action on a normal hotkey row
- [ ] The generator emits both halves of a modifier rebind from one row
- [ ] The known-shortcut catalog accounts for the composite rebind when it checks for conflicts
- [ ] The existing `Remap` action kind keeps working unchanged, and no existing row is migrated into the new concept
- [ ] A profile with no composite rebind behaves exactly as it does today

## Out of scope

- The existing simple `Remap` action kind. It already ships and this item leaves it alone
- Known-shortcut warnings for simple remaps. That is an existing gap, tracked as item 044
- Storing composite rebinds as ordinary hotkey rows with new prefix columns. That is the approach this item rejects
- Rebinding mouse buttons. The key registry has no mouse entries yet

## Notes / dependencies

- Item 043 is the accepted answer for now. Revisit only when snippets prove insufficient
- Item 044 covers the conflict-warning gap for simple remaps. It does not depend on this item
- Whoever picks this up should start from the conflict-warning problem, not from the emitter
