using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class Hotkey
{
    private Hotkey()
    {
        Description = string.Empty;
        Key = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Description { get; private set; }
    public string Key { get; private set; }
    public bool Ctrl { get; private set; }
    public bool Alt { get; private set; }
    public bool Shift { get; private set; }
    public bool Win { get; private set; }
    public HotkeyActionKind ActionKind { get; private set; }
    public string? Text { get; private set; }
    public string? SendKeysContent { get; private set; }
    public string? RunTarget { get; private set; }
    public RunTargetKind? RunTargetKind { get; private set; }
    public WindowOp? WindowOp { get; private set; }
    public string? RemapDest { get; private set; }
    public string? Body { get; private set; }
    public bool AppliesToAllProfiles { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotkeyProfile> Profiles { get; private set; } = [];
    public ICollection<HotkeyCategory> Categories { get; private set; } = [];

    public static Hotkey Create(Guid ownerOid, HotkeyDefinition definition, TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        Hotkey hk = new()
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            CreatedAt = now,
            UpdatedAt = now,
        };
        hk.Apply(definition);
        return hk;
    }

    public static Hotkey Restore(
        Guid id,
        Guid ownerOid,
        HotkeyDefinition definition,
        DateTimeOffset createdAt,
        TimeProvider clock)
    {
        Hotkey hk = new()
        {
            Id = id,
            OwnerOid = ownerOid,
            CreatedAt = createdAt,
            UpdatedAt = clock.GetUtcNow(),
        };
        hk.Apply(definition);
        return hk;
    }

    public void Update(HotkeyDefinition definition, TimeProvider clock)
    {
        Apply(definition);
        UpdatedAt = clock.GetUtcNow();
    }

    private void Apply(HotkeyDefinition definition)
    {
        Description = definition.Description;
        Key = definition.Key;
        Ctrl = definition.Ctrl;
        Alt = definition.Alt;
        Shift = definition.Shift;
        Win = definition.Win;
        AppliesToAllProfiles = definition.AppliesToAllProfiles;
        ActionKind = definition.ActionKind;
        Text = definition.Text;
        SendKeysContent = definition.SendKeysContent;
        RunTarget = definition.RunTarget;
        RunTargetKind = definition.RunTargetKind;
        WindowOp = definition.WindowOp;
        RemapDest = definition.RemapDest;
        Body = definition.Body;
    }
}
