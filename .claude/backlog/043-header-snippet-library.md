# 043 - Header snippet library

## Metadata

- **Epic**: Profiles
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

A profile header is an empty box with a few default lines in it. Anything beyond that has to be typed from memory, in a language most owners do not write daily. Ship a short list of ready-made header blocks that an owner can pick from a list and drop straight into the header.

## User story

As an owner, I want to pick a common header setting from a list, so that I do not have to write AutoHotkey by hand to change how my whole profile behaves.

## Background

`Profile.HeaderTemplate` is free text with a length limit and nothing else. It already holds the directives every generated script needs, so it is the right home for settings that apply to a whole profile rather than to one shortcut.

Snippets are shipped constants, in the same shape as the existing sample-hotkey catalog. No new table, no migration, no create or edit screens.

The catalog lives in the Application project and the API reads it out. The sample-hotkey catalog it copies is `internal`, so the Blazor project cannot reference it. The key registry has the same problem and already solves it: `ListHotkeyKeysQuery` turns the internal constants into DTOs, and `HotkeysController` serves them. Snippets follow that path exactly. There must be one catalog, not a backend copy and a frontend copy.

## How it works

Picking a snippet appends its text to the end of the header, wrapped in marker comments. The shape, with the body left as a placeholder because no body is verified yet:

```ahk
; --- AHKFlow snippet: <snippet-id> ---
<snippet body>
; --- end <snippet-id> ---
```

The markers let the picker grey out a snippet that is already in the header, and let an owner find one to remove by hand.

**Inserting copies the text.** After that the text belongs to the owner. A later app version that improves a snippet does not change profiles that already took it. This is deliberate — the alternative is an owner who cannot edit their own header.

### Where the text lands

"Append" needs an exact rule, because an owner's header may not end with a newline.

- The insert adds a blank line, then the opening marker. If the header does not already end with a line break, one is added first. A marker must never join the owner's last line of code
- The insert leaves the header ending with a single newline, so the next insert behaves the same way
- A header that is empty gets no leading blank line

### Size

`HeaderTemplate` is capped at 8,000 characters by `ProfileRules.HeaderTemplateMaxLength`. The picker must check before it inserts, not after.

- If the header plus the snippet plus its markers would pass the cap, the insert is refused and the owner is told why
- The header is left untouched when an insert is refused

## Proposed first set

Five snippets, grouped by tag so the picker can order them:

- **Keyboard layer** — Caps Lock acts as several modifiers at once; Right Alt acts as several modifiers at once
- **Lock keys** — keep Num Lock, Caps Lock, and Scroll Lock switched off
- **Application behaviour** — pause all shortcuts while one named application is in front
- **Typing** — choose which characters finish a hotstring

The "pause while an application is in front" snippet needs an application name. Ship it with a clearly marked placeholder and a comment saying to replace it. Prompting for the value is a second feature and not wanted here.

### What a snippet must not do

A snippet exists for whole-profile behaviour that a hotkey row cannot express. Anything a row already does belongs in a row, where it gets editing, history, and conflict checking. Three earlier candidates were dropped for that reason:

- **Caps Lock acts as Ctrl** — the `Remap` action kind already emits `CapsLock::Ctrl` from an ordinary row
- **Reload, pause, and exit the script** — ordinary `Raw` rows. "Reload AHK script" already ships as a sample hotkey in `DefaultHotkeyCatalog`
- **Turn Caps Lock off completely** — the lock-keys snippet already covers it, and a `Disable` row covers the narrower "stop the key doing anything" case

This is the same test that keeps clipboard hotkeys out. Applying it to some candidates and not others is what produced the first draft's overlap.

## Acceptance criteria

- [ ] A snippet catalog exists in the Application project as shipped constants, each entry carrying a stable id, name, one-line description, tag, and body
- [ ] The API serves the catalog read-only, through a query and controller action, the same way the hotkey key registry is served
- [ ] The Blazor project reads the catalog from that endpoint and holds no copy of the bodies
- [ ] The profile header editor has a control that opens the picker, grouped by tag
- [ ] Picking a snippet appends it to the header, wrapped in the marker comments
- [ ] A header that does not end with a line break gets one before the opening marker, so a marker never joins the owner's last line
- [ ] An insert that would push the header past `ProfileRules.HeaderTemplateMaxLength` is refused with a message, and the header is left unchanged
- [ ] A snippet already present in the header is shown as unavailable
- [ ] No snippet body repeats a directive the default header already emits
- [ ] Every snippet body survives header rendering unchanged
- [ ] Every snippet body is checked against the project's AutoHotkey v2 syntax reference before it ships
- [ ] No snippet is inserted on its own. A newly created profile and a lazily seeded profile both have a header with no snippet markers in it

## Out of scope

- Owner-created snippets. Shipped list only
- Adding any snippet to a profile automatically. Every insert is an explicit choice. A keyboard layer or a lock-key setting changes how the whole machine behaves, so it must never arrive without being asked for
- Whole-profile templates that set header and footer together when a profile is created
- Seeding sample hotstrings or hotkeys. That is content, and a separate concern
- Editing a snippet after it has been inserted. It is plain header text at that point
- Anything a hotkey row already expresses. See "What a snippet must not do" above

## Notes / dependencies

- Two constraints decide whether a snippet is allowed, and both should be enforced by a unit test over the catalog rather than by review:
  - The header renderer turns a doubled brace into a single brace, so no body may contain one
  - The default header already sets several directives, and repeating one causes a warning or wrong behaviour
- These bodies are AutoHotkey the project has never generated. Treat each one as unverified until checked against the syntax reference — do not copy them from an existing script without reading it first
- Related: item 042 explains why *composite* key rebinds ship as snippets rather than as rows. Simple remaps are already rows and stay that way
