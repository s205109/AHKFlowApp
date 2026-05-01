namespace AHKFlowApp.Domain.Entities;

public sealed class Hotkey
{
    private Hotkey()
    {
        Trigger = string.Empty;
        Action = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public Guid? ProfileId { get; private set; }
    public string Trigger { get; private set; }
    public string Action { get; private set; }
    public string? Description { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static Hotkey Create(
        Guid ownerOid,
        string trigger,
        string action,
        string? description,
        Guid? profileId,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Hotkey
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            ProfileId = profileId,
            Trigger = trigger,
            Action = action,
            Description = description,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void Update(
        string trigger,
        string action,
        string? description,
        Guid? profileId,
        TimeProvider clock)
    {
        Trigger = trigger;
        Action = action;
        Description = description;
        ProfileId = profileId;
        UpdatedAt = clock.GetUtcNow();
    }
}
