# CLI hotstrings reference

`ahkflow hotstring` manages hotstrings from the command line. This page documents the
actual CLI surface and how each hotstring kind renders in `list` output.

## Commands

- `ahkflow hotstring new` — creates a **Text** hotstring, or a **Raw** hotstring with `--raw`.
  - **Text:** `--trigger`/`-t` and `--replacement`/`-r`; `--profile`/`-p` is repeatable;
    `--no-ending-char` and `--no-inside-word` flip the two boolean options (both default to their
    "on" behavior).
  - **Raw:** `--raw "<definition>"` sends the entire verbatim AHK v2 definition (e.g.
    `:K1000 SE*:ftw::for the win`); the server derives the trigger and validates it. `--raw` is
    **mutually exclusive** with `--trigger`/`--replacement`. `--profile` still applies.
  - Date & time and Macro kinds cannot be created via the CLI yet — create them in the web UI,
    then they show up (display-only) in `ahkflow hotstring list`.
- `ahkflow hotstring list` — lists hotstrings of **all** kinds. Supports `--profile`/`-p`,
  `--search`/`-s`/`-g`, `--page`, `--page-size`, and `--json`. There is **no** `--kind` filter
  and **no** `hotstring update` command in the CLI today.

## `list` table columns

| Column | Contents |
|---|---|
| Trigger | The abbreviation, truncated to 20 chars. |
| Kind | `Text`, `DateTime`, `Macro`, or `Raw`. |
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
- **Raw** — only the **first line** of the verbatim definition (the `:options:trigger::` line),
  truncated to 40 chars. A multi-line brace-body definition shows just its opening line so the
  table stays one row per hotstring; use the web UI to see (or edit) the full definition.

## Raw validation limitations

A Raw definition is the entire verbatim AHK v2 hotstring, validated (server-side) against a
deliberately **restricted subset** of AHK v2:

- The first non-blank line must be a `:options:trigger::` definition, and the paste must contain
  exactly **one** definition.
- The derived trigger must be non-empty, ≤ 40 characters (AHK's own abbreviation limit), and free
  of line breaks/tabs — so a trigger using escaped tab/newline (`` `t ``/`` `n ``) is rejected.
- Every option flag must be a known AHK v2 flag; `X0` and other undocumented off-forms are rejected.
- No line may start with `#` (directive lines corrupt the generated `#HotIf` grouping).
- A bare `::` first line requires a `{` brace body on its own line, with balanced braces and no
  content after the closing `}`. Brace counting is **string- and comment-unaware** — a `{` inside a
  quoted string (e.g. `SendText "{"`) counts toward the balance and is falsely rejected. Inline
  replacements are exempt from the brace check.
- **OTB** brace placement (`::btw:: {`) and **continuation sections** (`(` … `)`) are rejected with
  actionable messages. These are deliberate limitations, not bugs; supporting them is a possible
  follow-up.

## Example

```
Trigger               Kind      Replacement                               Profiles                  Context                 Updated
--------------------  --------  ----------------------------------------  ------------------------  ----------------------  -------------------
btw                   Text      by the way                                all                                               2026-07-11 09:00:00
dd                    DateTime  yyyy-MM-dd (+7 days)                      all                                               2026-07-11 09:00:00
htag                  Macro     <b>{{cursor}}</b>                         all                                               2026-07-11 09:00:00
ftw                   Raw       :K1000 SE*:ftw::for the win               all                                               2026-07-11 09:00:00
```
