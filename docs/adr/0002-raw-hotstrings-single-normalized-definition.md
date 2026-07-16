# Raw hotstrings store one normalized definition, not decomposed option fields

A Raw hotstring is persisted as a single AutoHotkey definition rather than decomposed into the structured option columns the other kinds use. Structured fields cannot express the full set of AHK v2 option flags, and Raw exists precisely for the users who need the exotic ones; keeping the definition text the single source of truth stops it and any derived fields from drifting apart.

The stored text is normalized, not byte-for-byte what the user pasted: one save-time pass converts line endings, trims trailing whitespace outside continuation sections, expands a one-true-brace body onto its own line, and lifts leading `;` comments into the item's description. A Trigger is derived from the definition and stored beside it for display, lookup, and uniqueness checks — but it is derived, never edited independently, and the option-flag columns are ignored.

Raw replaced an earlier `Script` kind. That retired value is still accepted when reading old Snapshots — new definitions using it are rejected, and old ones are converted to Raw on Revert or Restore.

## Consequences

Undoing this means parsing every Raw definition back into structured fields, which is lossy for exactly the options Raw was added to preserve. The migration onto Raw was deliberately one-way.
