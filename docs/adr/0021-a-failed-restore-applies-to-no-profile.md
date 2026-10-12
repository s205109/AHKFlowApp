# A failed Restore applies to no profile, and a failed Revert is refused

Restore and Revert check the definition they are about to apply against the same rules a new save
must pass. The two then answer a failure differently, on purpose.

A **Revert** that fails is refused. The handler returns `Result.Invalid(errors)` and leaves the live
hotstring or hotkey exactly as it was.

A **Restore** that fails still brings the item back, but **Applies to no profile**: the handler
attaches no Profile and sets `AppliesToAllProfiles` to false, whatever the Snapshot said. The
response names every rule that failed. No Profile script contains the item until the Owner repairs
it in the edit dialog, where the ordinary Update rules refuse the save while a bad value remains.

## Why the two differ

The harm is not symmetric, and neither is the Owner's way out.

A refused Revert costs the Owner one unreachable Version. The live item still works, and every other
Version is still there. Nothing is lost that the Owner cannot reach another way.

A refused Restore costs the Owner the whole item. An Owner cannot edit a Tombstone, so there is no
step they can take to make a stored Snapshot pass. The refusal is permanent for that item, and the
Recycle Bin held the last copy.

Accepting a failing Restore unchanged is worse than either. One bad value is written raw into the
generated script — an unescaped window context, a Remap with no destination — so the whole Profile
script stops loading, or generation throws. One lost item becomes every item in that Profile, and
the Owner finds out only when they download the script and run it.

**Applies to no profile** is the only state that keeps the data and cannot reach a script. The
Emitter reads an item through its Profile links, so an item with no links is emitted nowhere. That
needs no change to any Emitter, and no new column.

## Considered Options

**Refuse both.** Simpler, and one rule instead of two. Rejected because it makes a deleted item
unrecoverable for a reason the Owner cannot act on. That reason stands on its own.

A second consideration points the same way, and it is worth stating precisely rather than
overstating. ADR-0005 keeps the legacy converter as permanent runtime code and leaves stored
Snapshots unrewritten. It does not promise that a Restore always succeeds, so refusing one would not
breach it. What refusing both would do is make the converter pointless for a subset of rows: a
pre-registry Snapshot can hold a `Key` the canonical registry now refuses, and a legacy
`Kind=Script` hotstring Snapshot can compose into a Raw definition whose derived trigger breaks the
Raw 40-character cap. The converter would still run on those rows and the restore would still fail.
Keeping them recoverable honours what ADR-0005 was for.

**Accept both unchanged, with a warning.** Rejected: the warning arrives in the UI while the broken
value is already in the next generated script, and a Profile script that does not load is a larger
loss than the item it came from.

**Keep `AppliesToAllProfiles` true and have the Emitter skip the item.** Rejected: it needs a
persisted "needs repair" column and moves input checking into the Emitters, which backlog 162 puts
out of scope. The Emitters keep trusting validated input.

**Refuse a Restore only when the Snapshot applies to all Profiles.** Rejected: that is the default
for a new item, so the exception would quietly become the rule for most items.

## Consequences

1. **Restore can write a value the Snapshot did not say.** `AppliesToAllProfiles` is forced to
   false. ADR-0003 frames history as point-in-time Snapshots, and this does not rewrite one: the
   stored Snapshot is untouched, and the Restore Snapshot records the state actually brought back,
   which is what `CONTEXT.md` says a Restore Snapshot holds.
2. **A restored item still occupies its trigger.** The per-Owner unique index does not read Profile
   links, so the Owner cannot create a fresh item with the same trigger until they repair or delete
   the restored one.
3. **"Applies to no profile" has two causes that look identical.** An item can also reach it because
   the Owner deleted every Profile it named, which Restore already allowed before this decision.
   Nothing persisted tells the two apart. Only the Restore response carries the rule messages.
4. **The rules now have a second caller.** A rule tightened for Create and Update immediately
   governs Restore and Revert as well. That is the point of the decision, and it means a future
   tightening can refuse a Revert that worked the day before.
5. **For one family of stored rows, the edit dialog is not a way out.** The decision above rests on
   the Owner repairing the item in the edit dialog. That holds for a value the Owner can retype, such
   as a window context or a Key. It does not hold when the rule that failed is the brace counter in
   `AddRawKindRules`, which decision D12 keeps deliberately unaware of strings and comments. A legacy
   `Kind=Script` body that sends a literal brace, such as `Send "{{}"`, composes into a Raw
   definition the counter reads as unbalanced, even though AutoHotkey accepts it. Before this
   decision that row restored attached and its generated line was unchanged. Now it comes back
   applying to no profile, and `UpdateHotstringCommandValidator` runs the same rule, so every save
   is refused while the body stays as it is. The Owner's only routes are rewriting the body into a
   brace-balanced equivalent or changing the kind to Text and losing the code. A Revert to such a
   version is refused outright.

   We accepted this rather than drop the brace rule from the Restore and Revert rule set. Dropping
   it would let Restore accept a definition the edit dialog then refuses forever, which is a worse
   state than an item the Owner can at least see and rewrite. The behavior is pinned by
   `DefinitionRuleCheckTests.Check_LegacyScriptBodyWithLiteralBrace_PinsTheNaiveBraceCounter`, so a
   later change to D12 shows up as a failing test rather than a silent change of outcome.

The honest cost: two code paths answer one question two ways, and a reader has to know why. This
record is that reason.

## Revisit if

An "enabled" flag is ever added to a hotstring or hotkey. Detaching from every Profile is the only
lever available today precisely because no such flag exists. A flag would make the state explicit,
let Restore keep `AppliesToAllProfiles` as the Snapshot wrote it, and remove consequence 3.
