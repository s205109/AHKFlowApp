namespace AHKFlowApp.Domain.Entities;

public sealed class Category
{
    private Category()
    {
        Name = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Name { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotstringCategory> Hotstrings { get; private set; } = [];
    public ICollection<HotkeyCategory> Hotkeys { get; private set; } = [];

    public static Category Create(Guid ownerOid, string name, TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Category
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Name = name,
            CreatedAt = now,
            UpdatedAt = now,
        };
    }

    public void Update(string name, TimeProvider clock)
    {
        Name = name;
        UpdatedAt = clock.GetUtcNow();
    }
}
