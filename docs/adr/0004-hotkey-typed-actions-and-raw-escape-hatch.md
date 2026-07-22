# Hotkeys store a typed Action, with Raw as the only verbatim path

A hotkey's Action is persisted as a discriminated set of typed columns — an `ActionKind` plus the one or two columns that kind owns (`Text`, `SendKeysContent`, `RunTarget` + `RunTargetKind`, `WindowOp`, `RemapDest`, `Body`) — rather than one free string or a JSON payload. The kind is what the validator, the emitter, the DTOs and the history snapshot all branch on: each kind declares which field it requires, forbids the others, and has exactly one emission rule. A kind the emitter does not know throws instead of writing a line, so an Action that cannot be generated cannot be stored.

That is what closes the injection hazard the feature carried (issue #195), and it closes it on both sides of the `::`. The left-hand side is never free text: modifiers are booleans and the key is a canonical registry name or a `vkNN`/`scNNN` code, both validated at the create and update boundaries. On the right, the three kinds that embed user text (`SendText`, `SendKeys`, `Run`) pass it through the shared `AhkEscaping.EscapeStringLiteral`; `SendKeys` and `Remap` additionally persist a token validated against the key registry; `Window` emits from an enum and `Disable` emits a fixed word. No Action, Raw included, can break the line it is defined on.

**Raw is the sole verbatim path, and it is not sandboxed.** Its `Body` is emitted exactly as stored — no wrapper is added, so a block body carries its own braces. AutoHotkey parses the whole file at load, so a syntax error in one Raw body aborts the **entire** Profile script rather than just its own binding, and the brace-balance check counts `{` and `}` with no awareness of string literals or comments, so a body can also close its block early and have its remainder parsed at top level. This is the same trade-off already accepted for Raw hotstrings (ADR-0002, and *Known limitations* in `docs/development/ahk-v2-syntax.md`): a string- and comment-aware scanner would drift toward being a script IDE. Raw must therefore be presented as unchecked AutoHotkey wherever it is offered.

## Migrating off the legacy pair

The typed columns replaced a two-value `HotkeyAction` plus one opaque `Parameters` string, in two migrations rather than one: the first adds the typed columns and back-fills them, a later one drops the legacy pair, so every commit in between runs against a database of either shape. The back-fill is hand-written T-SQL and the identical transform exists in C# as `LegacyHotkeyDefinitionConverter`, because history JSON written before the change still has to be read on Restore and Revert; a Testcontainers parity test runs the same fixtures through both and requires identical output.

The mapping preserves what the app already emitted: `Run` becomes `Run`; a `Send` whose parameters parse as a valid key token becomes `SendKeys`; every other `Send` becomes `Raw` with a body reproducing the previously emitted `Send("…")` line byte for byte. Downloading an untouched profile after the migration therefore yields the same file as before it — which is the reason Raw emits verbatim instead of wrapping the body in braces.

## Consequences

Adding an Action kind is now a schema change plus a branch in the validator, emitter, DTOs and snapshot converter, not a new convention inside a string. That cost is the point: the alternative fails at script-load time on the user's machine, where we cannot see it.

Snapshots are immutable, so pre-existing history keeps its legacy `Action`/`Parameters` members forever and the converter can never be deleted — only the live columns were dropped.
