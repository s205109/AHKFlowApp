# AHKFlow - Claude Design Brief

## Purpose

This brief gives Claude Design product context without requiring the full .NET architecture overview.

Use this document for UI design direction, screen composition, visual hierarchy, and product experience decisions. For the engineering overview, see [Product Vision & .NET Architecture Overview](product-vision.md).

## Product Promise

**AutoHotkey Hotstring Manager & CLI.** AHKFlow helps Windows users manage AutoHotkey hotstrings and hotkeys in one structured place, organize them by profile and category, preview the resulting scripts, and download valid `.ahk` files. It ships with two first-class interfaces: the Blazor web UI and the `ahkflow` CLI.

## Target Experience

AHKFlow should feel like a focused productivity tool:

- Dense enough for repeated operational use.
- Clear enough for users with many automations.
- Calm and utilitarian, not marketing-heavy.
- Fast to scan, filter, edit, and confirm.
- Transparent about how managed definitions become generated scripts.

## Primary Users

- Windows users who rely on AutoHotkey for text expansion and shortcuts.
- Power users who want CLI access for scripted workflows.
- Developers or technical users who want maintainable automation definitions instead of scattered `.ahk` files.

## Core Screens

- **Dashboard** - Compact overview of totals, recent activity, and entry points.
- **Hotstrings** - Searchable/editable table and mobile list for text replacement definitions.
- **Hotkeys** - Searchable/editable table and mobile list for keyboard shortcut definitions.
- **Profiles** - Profile management, default selection, header/footer templates, and script preview.
- **Categories** - Tag management for organizing hotstrings and hotkeys.
- **Downloads** - Per-profile `.ahk` downloads and all-profile zip download.

## Core Data Concepts

- **Hotstring** - Abbreviation plus replacement text.
- **Hotkey** - Modifier keys, trigger key, action, and action parameters.
- **Profile** - A named group that produces one generated `.ahk` script.
- **Category** - A tag used to organize and filter definitions.
- **Generated script** - The output file users preview and download.

## Design Priorities

- Make create/edit/delete flows direct and predictable.
- Keep tables readable, with clear filters and stable row actions.
- Preserve parity between desktop tables and mobile list/card layouts.
- Surface profile/category assignment clearly because those choices affect generated scripts.
- Make preview/download actions feel connected to profiles.
- Use concise labels and avoid instructional copy that explains obvious UI controls.

## Out of Scope For Design Work

- Runtime execution of AutoHotkey scripts.
- Custom unmanaged `.ahk` file editing.
- Hotkey blacklisting.
- Terminal/CLI visual styling. The `ahkflow` CLI ships as a first-class interface, but its plain-text presentation is outside this web UI design brief.
