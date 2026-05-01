namespace AHKFlowApp.Domain.Entities;

public sealed class Profile
{
    private Profile()
    {
        Name = string.Empty;
        HeaderTemplate = string.Empty;
        FooterTemplate = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Name { get; private set; }
    public bool IsDefault { get; private set; }
    public string HeaderTemplate { get; private set; }
    public string FooterTemplate { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static Profile Create(
        Guid ownerOid,
        string name,
        bool isDefault,
        string headerTemplate,
        string footerTemplate,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Profile
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Name = name,
            IsDefault = isDefault,
            HeaderTemplate = headerTemplate,
            FooterTemplate = footerTemplate,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void Update(string name, string headerTemplate, string footerTemplate, TimeProvider clock)
    {
        Name = name;
        HeaderTemplate = headerTemplate;
        FooterTemplate = footerTemplate;
        UpdatedAt = clock.GetUtcNow();
    }

    public void MarkDefault(bool isDefault, TimeProvider clock)
    {
        IsDefault = isDefault;
        UpdatedAt = clock.GetUtcNow();
    }
}
