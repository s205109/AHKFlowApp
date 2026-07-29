namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// One built-in shortcut use an owner has silenced. Per use, not per combination: silencing the
/// Windows use of Win+E leaves any other use of the same keys still warning. Owner-recorded uses
/// are removed by deleting the record, so they are never ignored.
/// </summary>
public sealed class IgnoredKnownShortcut
{
    private IgnoredKnownShortcut()
    {
        ShortcutId = string.Empty;
        UsedBy = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }

    /// <summary>Built-in id, for example "windows.file-explorer". A later release may retire one.</summary>
    public string ShortcutId { get; private set; }

    /// <summary>Which use of that shortcut is silenced.</summary>
    public string UsedBy { get; private set; }

    public DateTimeOffset CreatedAt { get; private set; }

    public static IgnoredKnownShortcut Create(Guid ownerOid, string shortcutId, string usedBy, TimeProvider clock) =>
        new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            ShortcutId = shortcutId,
            UsedBy = usedBy,
            CreatedAt = clock.GetUtcNow(),
        };
}
