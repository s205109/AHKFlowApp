using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

public sealed class Hotkey
{
    private Hotkey()
    {
        Description = string.Empty;
        Key = string.Empty;
        Parameters = string.Empty;
    }

    public Guid Id { get; private set; }
    public Guid OwnerOid { get; private set; }
    public string Description { get; private set; }
    public string Key { get; private set; }
    public bool Ctrl { get; private set; }
    public bool Alt { get; private set; }
    public bool Shift { get; private set; }
    public bool Win { get; private set; }
    public HotkeyAction Action { get; private set; }
    public string Parameters { get; private set; }
    public bool AppliesToAllProfiles { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public ICollection<HotkeyProfile> Profiles { get; private set; } = [];

    public static Hotkey Create(
        Guid ownerOid,
        string description,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        HotkeyAction action,
        string parameters,
        bool appliesToAllProfiles,
        TimeProvider clock)
    {
        DateTimeOffset now = clock.GetUtcNow();
        return new Hotkey
        {
            Id = Guid.NewGuid(),
            OwnerOid = ownerOid,
            Description = description,
            Key = key,
            Ctrl = ctrl,
            Alt = alt,
            Shift = shift,
            Win = win,
            Action = action,
            Parameters = parameters,
            AppliesToAllProfiles = appliesToAllProfiles,
            CreatedAt = now,
            UpdatedAt = now,
        };
    }

    public void Update(
        string description,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        HotkeyAction action,
        string parameters,
        bool appliesToAllProfiles,
        TimeProvider clock)
    {
        Description = description;
        Key = key;
        Ctrl = ctrl;
        Alt = alt;
        Shift = shift;
        Win = win;
        Action = action;
        Parameters = parameters;
        AppliesToAllProfiles = appliesToAllProfiles;
        UpdatedAt = clock.GetUtcNow();
    }
}
