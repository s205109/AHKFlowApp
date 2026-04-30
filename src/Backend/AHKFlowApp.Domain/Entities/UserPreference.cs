namespace AHKFlowApp.Domain.Entities;

public sealed class UserPreference
{
    private UserPreference() { }

    public Guid OwnerOid { get; private set; }
    public int RowsPerPage { get; private set; }
    public bool DarkMode { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

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
}
