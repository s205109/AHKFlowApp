# Raw hotstrings are stored verbatim, not decomposed

A Raw hotstring keeps the user's entire AutoHotkey definition exactly as written, and its Trigger and option flags are read back out of that text rather than stored beside it. Structured fields cannot express the full set of AHK v2 option flags, and Raw exists precisely for the users who need the exotic ones; making the written text the single source of truth is what stops the definition and its derived fields from drifting apart.

Raw replaced an earlier `Script` kind. That retired value is still accepted when reading old Snapshots — new definitions using it are rejected, and old ones are converted to Raw on Revert or Restore.

## Consequences

Undoing this means parsing every Raw definition back into structured fields, which is lossy for exactly the options Raw was added to preserve. The migration onto Raw was deliberately one-way.
