# 037 - Raw body duplicate hotkey detection

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Detect when a Raw hotkey body defines a hotkey that another hotkey in the same Profile already defines.
AutoHotkey treats a duplicate hotkey as a load error, and that error stops the **whole** Profile script
from loading — not just the offending line.

## User story

As an Owner, I want to be told when a Raw body redefines a key another hotkey already uses, so that one
paste does not stop my entire Profile script from loading.

## Acceptance criteria

- [x] A Raw body line that opens a new top-level hotkey definition is rejected before saving.
- [x] A Raw body line that opens a new top-level hotstring definition is rejected before saving.
- [x] The message names the line number, so the Owner can find it.
- [x] A definition-looking line inside braces, inside a string, inside a line or block comment, or
      inside a continuation section is still accepted.
- [x] Generated `.ahk` output is unchanged.

Implemented as rejection, not comparison — see the design decision note below.

## Out of scope

- Parsing or validating the rest of the Raw body. `ahk-v2-syntax.md` already records that the existing
  brace counter errs deliberately rather than drift toward being a script IDE, and the same limit
  applies here.
- `#HotIf` context awareness. Not needed: the chosen design rejects the injection itself rather than
  comparing combinations, so context scope never enters the decision. (Hotkeys do carry window context
  fields today — `Hotkey.ContextMatchType`/`ContextValue`, added 2026-07-31 — the "hotkeys carry no
  context fields" note below was true when this item was filed and is now stale.)
- Known shortcuts. That is a different concept and a different mechanism — see
  `docs/superpowers/specs/2026-07-28-hotkey-conflict-warnings-design.md`.
- Fixing the pre-existing Raw body field inline-error rendering bug found while implementing this item.
  See `.claude/backlog/051-hotkey-raw-body-inline-error-not-rendering.md`.

## Notes / dependencies

- **Design decision, 2026-08-03:** implemented as *rejecting the injection*, not *comparing for
  duplicates*. A Raw body may no longer contain a line that opens a new top-level hotkey or hotstring
  definition at all (`RawHotkeyBodyScanner`, wired into `HotkeyRules.AddHotkeyActionRules`). This
  removes the injection itself, so a Raw body can never introduce a duplicate combination — no database
  query, no key normalization, no owner/context scope rule, and no false duplicate report can block a
  valid save. It also closes a case duplicate comparison alone would have missed: two different Raw
  bodies each injecting the same combination, where neither collides with a stored combination. Full
  reasoning: `docs/superpowers/specs/2026-08-03-raw-hotkey-body-definition-guard-design.md`.
- Found while designing hotkey shortcut warnings, and deliberately kept out of it. The two are often
  confused, so the distinction matters: this is a **duplicate**, which AHKFlow blocks, and it is
  detectable from data AHKFlow already holds. A **known shortcut** is something outside AHKFlow using a
  combination, which can only be warned about from a curated list.
- This is the higher-severity failure of the two. A known shortcut costs one hotkey; a duplicate costs
  the entire Profile script.
- `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md` states the risk and gives the exact
  case: a body of `return` followed by a second line `^a::Run("calc")` passed validation before this
  item and injected a whole new top-level definition. The ADR carries a dated amendment recording that
  this example no longer passes.
- Typed hotkeys are already safe. The unique index at
  `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs:61-74` is
  owner-wide, so two typed hotkeys can never share a combination. Raw bodies bypass it because the
  combination lives in free text rather than in the `Key` and modifier columns.
