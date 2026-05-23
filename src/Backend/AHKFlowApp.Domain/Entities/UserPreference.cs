namespace AHKFlowApp.Domain.Entities;

public sealed class UserPreference
{
    private UserPreference() { }

    public Guid OwnerOid { get; private set; }
    public int RowsPerPage { get; private set; }
    public bool DarkMode { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }
    public DateTimeOffset? CategoriesSeededAt { get; private set; }
    public DateTimeOffset? HotstringsSeededAt { get; private set; }
    public DateTimeOffset? HotkeysSeededAt { get; private set; }

    public static UserPreference CreateDefault(Guid ownerOid, TimeProvider clock) => new()
    {
        OwnerOid = ownerOid,
        RowsPerPage = 10,
        DarkMode = false,
        UpdatedAt = clock.GetUtcNow()
    };

    public void Update(int rowsPerPage, bool darkMode, TimeProvider clock)
    {
        RowsPerPage = rowsPerPage;
        DarkMode = darkMode;
        UpdatedAt = clock.GetUtcNow();
    }

    public void MarkCategoriesSeeded(TimeProvider clock)
    {
        if (CategoriesSeededAt is not null) return; // idempotent
        DateTimeOffset now = clock.GetUtcNow();
        CategoriesSeededAt = now;
        UpdatedAt = now;
    }

    public void MarkHotstringsSeeded(TimeProvider clock)
    {
        if (HotstringsSeededAt is not null) return; // idempotent
        DateTimeOffset now = clock.GetUtcNow();
        HotstringsSeededAt = now;
        UpdatedAt = now;
    }

    public void MarkHotkeysSeeded(TimeProvider clock)
    {
        if (HotkeysSeededAt is not null) return; // idempotent
        DateTimeOffset now = clock.GetUtcNow();
        HotkeysSeededAt = now;
        UpdatedAt = now;
    }
}
