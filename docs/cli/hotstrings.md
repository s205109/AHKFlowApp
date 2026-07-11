# CLI hotstrings reference

`ahkflow hotstring` manages hotstrings from the command line. This page documents the
actual CLI surface and how each hotstring kind renders in `list` output.

## Commands

- `ahkflow hotstring new` — creates a **Text** hotstring only. `--trigger`/`-t` and
  `--replacement`/`-r` are required; `--profile`/`-p` is repeatable; `--no-ending-char` and
  `--no-inside-word` flip the two boolean options (both default to their "on" behavior).
  Advanced kinds (Date & time, Macro, Script) cannot be created via the CLI yet — create them
  in the web UI, then they show up (display-only) in `ahkflow hotstring list`.
- `ahkflow hotstring list` — lists hotstrings of **all** kinds. Supports `--profile`/`-p`,
  `--search`/`-s`/`-g`, `--page`, `--page-size`, and `--json`. There is **no** `--kind` filter
  and **no** `hotstring update` command in the CLI today.

## `list` table columns

| Column | Contents |
|---|---|
| Trigger | The abbreviation, truncated to 20 chars. |
| Kind | `Text`, `DateTime`, `Macro`, or `Script`. |
| Replacement | Per-kind summary — see below. |
| Profiles | Resolved profile names, or `all`. |
| Context | Window-context summary (`exe:`/`class:`/`title:` prefix), blank when global. |
| Updated | Last-updated timestamp, local time. |

## Replacement column per kind

- **Text** — the raw replacement, truncated to 40 chars.
- **Date & time** — `{format}` alone, or `{format} (+N unit)` / `{format} (-N unit)` when a
  date offset is set. `—` when no format is set (shouldn't normally happen).
- **Macro** — the raw replacement **as-is**, including `{{cursor}}` / `{{key:...}}` tokens.
  The CLI does not summarize macro tokens (decided when Macro support landed): reproducing
  the web UI's token-chip rendering as a CLI text summary was judged not worth the added
  complexity, and remains a possible follow-up. Advanced-kind rows are otherwise
  read-only/display-only until their own CLI create/edit support lands (see the redesign
  spec's D6).
- **Script** — only the **first line** of the raw AutoHotkey body, truncated to 40 chars. A
  multi-line script shows just its opening line so the table stays one row per hotstring; use
  the web UI to see (or edit) the full body.

## Script validation limitations

Script bodies are validated (in the web UI, where they are created) by two naive rules: no
line may start with `#` (directive lines corrupt the generated `#HotIf` grouping), and braces
must balance. Brace counting is **string- and comment-unaware** — a `{` inside a quoted string
(e.g. `SendText "{"`) counts toward the balance and is falsely rejected. This is a deliberate
limitation, not a bug; work around it by splitting the line or wrapping the brace differently.

## Example

```
Trigger               Kind      Replacement                               Profiles                  Context                 Updated
--------------------  --------  ----------------------------------------  ------------------------  ----------------------  -------------------
btw                   Text      by the way                                all                                               2026-07-11 09:00:00
dd                    DateTime  yyyy-MM-dd (+7 days)                      all                                               2026-07-11 09:00:00
htag                  Macro     <b>{{cursor}}</b>                         all                                               2026-07-11 09:00:00
~ver                  Script    MsgBox A_AhkVersion                       all                                               2026-07-11 09:00:00
```
