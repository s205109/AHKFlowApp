using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// One use of a key combination that an owner recorded themselves. Record origin is the owner;
/// what uses the keys is <see cref="UsedBy"/> — an owner recording a Visual Studio shortcut has
/// not become the user of it.
/// </summary>
public sealed class CustomKnownShortcut
{
    private CustomKnownShortcut()
    {
        Key = string.Empty;
        UsedBy = string.Empty;
        Does = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }

    /// <summary>Canonical key. Canonicalized by the handler before this is built.</summary>
    public string Key { get; private set; }

    public bool Ctrl { get; private set; }
    public bool Alt { get; private set; }
    public bool Shift { get; private set; }
    public bool Win { get; private set; }

    /// <summary>What uses the keys — a product name, or any label the owner typed.</summary>
    public string UsedBy { get; private set; }

    /// <summary>Never Protected: that claim needs a pinned Microsoft source, which an owner cannot supply.</summary>
    public ShortcutProtection Protection { get; private set; }

    public ShortcutScope Scope { get; private set; }

    /// <summary>Lowercase verb phrase completing "&lt;UsedBy&gt; uses &lt;combo&gt; to …".</summary>
    public string Does { get; private set; }

    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static CustomKnownShortcut Create(
        Guid ownerOid,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        string usedBy,
        ShortcutProtection protection,
        ShortcutScope scope,
        string does,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new CustomKnownShortcut
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Key = key,
            Ctrl = ctrl,
            Alt = alt,
            Shift = shift,
            Win = win,
            UsedBy = usedBy,
            Protection = protection,
            Scope = scope,
            Does = does,
            CreatedAt = now,
            UpdatedAt = now,
        };
    }

    public void Update(
        string usedBy,
        ShortcutProtection protection,
        ShortcutScope scope,
        string does,
        TimeProvider clock)
    {
        UsedBy = usedBy;
        Protection = protection;
        Scope = scope;
        Does = does;
        UpdatedAt = clock.GetUtcNow();
    }
}
