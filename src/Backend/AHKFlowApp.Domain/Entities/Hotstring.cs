using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class Hotstring
{
    private Hotstring()
    {
        Trigger = string.Empty;
        Replacement = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Trigger { get; private set; }
    public string Replacement { get; private set; }
    public string? Description { get; private set; }
    public bool AppliesToAllProfiles { get; private set; }
    public bool IsEndingCharacterRequired { get; private set; }
    public bool IsTriggerInsideWord { get; private set; }
    public HotstringKind Kind { get; private set; }
    public bool IsCaseSensitive { get; private set; }
    public bool OmitEndingCharacter { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotstringProfile> Profiles { get; private set; } = [];
    public ICollection<HotstringCategory> Categories { get; private set; } = [];

    public static Hotstring Create(Guid ownerOid, HotstringDefinition definition, TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        Hotstring hs = new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            CreatedAt = now,
            UpdatedAt = now,
        };
        hs.Apply(definition);
        return hs;
    }

    public static Hotstring Restore(
        Guid id,
        Guid ownerOid,
        HotstringDefinition definition,
        DateTimeOffset createdAt,
        TimeProvider clock)
    {
        Hotstring hs = new()
        {
            Id = id,
            OwnerOid = ownerOid,
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
        hs.Apply(definition);
        return hs;
    }

    public void Update(HotstringDefinition definition, TimeProvider clock)
    {
        Apply(definition);
        UpdatedAt = clock.GetUtcNow();
    }

    private void Apply(HotstringDefinition definition)
    {
        Trigger = definition.Trigger;
        Replacement = definition.Replacement;
        Description = definition.Description;
        AppliesToAllProfiles = definition.AppliesToAllProfiles;
        IsEndingCharacterRequired = definition.IsEndingCharacterRequired;
        IsTriggerInsideWord = definition.IsTriggerInsideWord;
        Kind = definition.Kind;
        IsCaseSensitive = definition.IsCaseSensitive;
        OmitEndingCharacter = definition.OmitEndingCharacter;
    }
}
