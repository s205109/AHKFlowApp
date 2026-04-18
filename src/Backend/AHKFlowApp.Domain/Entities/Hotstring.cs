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
    public Guid? ProfileId { get; private set; }
    public string Trigger { get; private set; }
    public string Replacement { get; private set; }
    public bool IsEndingCharacterRequired { get; private set; }
    public bool IsTriggerInsideWord { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public static Hotstring Create(
        Guid ownerOid,
        string trigger,
        string replacement,
        Guid? profileId,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Hotstring
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            ProfileId = profileId,
            Trigger = trigger,
            Replacement = replacement,
            IsEndingCharacterRequired = isEndingCharacterRequired,
            IsTriggerInsideWord = isTriggerInsideWord,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void Update(
        string trigger,
        string replacement,
        Guid? profileId,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        TimeProvider clock)
    {
        Trigger = trigger;
        Replacement = replacement;
        ProfileId = profileId;
        IsEndingCharacterRequired = isEndingCharacterRequired;
        IsTriggerInsideWord = isTriggerInsideWord;
        UpdatedAt = clock.GetUtcNow();
    }
}
