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

## How it works

Picking a snippet appends its text to the end of the header, wrapped in marker comments:

```ahk
; --- AHKFlow snippet: capslock-ctrl ---
*CapsLock::Ctrl
; --- end capslock-ctrl ---
```

The markers let the picker grey out a snippet that is already in the header, and let an owner find one to remove by hand.

**Inserting copies the text.** After that the text belongs to the owner. A later app version that improves a snippet does not change profiles that already took it. This is deliberate — the alternative is an owner who cannot edit their own header.

## Proposed first set

Grouped by tag, so the picker can order them:

- **Keyboard layer** — Caps Lock acts as Ctrl; Caps Lock acts as several modifiers at once; Right Alt acts as several modifiers at once; turn Caps Lock off completely
- **Lock keys** — keep Num Lock, Caps Lock, and Scroll Lock switched off
- **Application behaviour** — pause all shortcuts while one named application is in front
- **Script control** — shortcuts to reload, pause, and exit the running script
- **Typing** — choose which characters finish a hotstring

The "pause while an application is in front" snippet needs an application name. Ship it with a clearly marked placeholder and a comment saying to replace it. Prompting for the value is a second feature and not wanted here.

## Acceptance criteria

- [ ] A snippet catalog exists as shipped constants, each entry carrying a stable id, name, one-line description, tag, and body
- [ ] The profile header editor has a control that opens the picker, grouped by tag
- [ ] Picking a snippet appends it to the header, wrapped in the marker comments
- [ ] A snippet already present in the header is shown as unavailable
- [ ] No snippet body repeats a directive the default header already emits
- [ ] Every snippet body survives header rendering unchanged
- [ ] Every snippet body is checked against the project's AutoHotkey v2 syntax reference before it ships

## Out of scope

- Owner-created snippets. Shipped list only
- Whole-profile templates that set header and footer together when a profile is created
- Seeding sample hotstrings or hotkeys. That is content, and a separate concern
- Editing a snippet after it has been inserted. It is plain header text at that point

## Notes / dependencies

- Two constraints decide whether a snippet is allowed, and both should be enforced by a unit test over the catalog rather than by review:
  - The header renderer turns a doubled brace into a single brace, so no body may contain one
  - The default header already sets several directives, and repeating one causes a warning or wrong behaviour
- These bodies are AutoHotkey the project has never generated. Treat each one as unverified until checked against the syntax reference — do not copy them from an existing script without reading it first
- Related: item 042 explains why key rebinds ship as snippets rather than as rows
