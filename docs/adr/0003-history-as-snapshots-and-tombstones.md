# History as snapshots and tombstones, with hard deletes

Editing or deleting a hotstring or hotkey records a Snapshot of its previous state in a separate history table; restoring a deleted one records the restored state, so a timeline holds both before-images and Restore after-images. Deletes remove the live row for real and leave a `Delete` Tombstone behind — the Recycle Bin reads from Tombstones, and Purge erases every remaining Snapshot for the item.

## Considered Options

Soft-delete columns and SQL Server temporal tables were both rejected. Soft delete would need either a global query filter (plus `IgnoreQueryFilters` wherever deleted rows must surface, like the Recycle Bin) or an explicit `IsDeleted` predicate in every query, and filtered versions of the per-owner unique indexes so a deleted row stops occupying its trigger. Snapshots leave the live tables and their semantics untouched — the migration was purely additive — and capture an item's category and profile links as one aggregate, matching how those links are replaced wholesale on edit.
