# History as before-image snapshots, with hard deletes and tombstones

Editing or deleting a hotstring or hotkey records a Snapshot of its previous state in a separate history table. Deletes remove the live row for real and leave a `Delete` tombstone Snapshot behind, so a deleted item's timeline ends at the tombstone and the Recycle Bin reads from there.

## Considered Options

Soft-delete columns and SQL Server temporal tables were both rejected. Hotstrings and hotkeys carry per-owner unique indexes (a soft-deleted row would still occupy its trigger, blocking a replacement), and neither entity has a global query filter — adding one would mean touching every existing query. Snapshots also capture an item's category and profile links as a single aggregate, which suits how those links are replaced wholesale on edit.
