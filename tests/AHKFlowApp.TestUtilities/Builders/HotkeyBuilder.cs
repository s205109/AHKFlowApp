using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotkeyBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private Guid? _profileId;
    private string _trigger = "^!K";
    private string _action = "Run notepad";
    private string? _description;
    private TimeProvider _clock = TimeProvider.System;

    public HotkeyBuilder WithOwner(Guid ownerOid)
    {
        _ownerOid = ownerOid;
        return this;
    }

    public HotkeyBuilder InProfile(Guid? profileId)
    {
        _profileId = profileId;
        return this;
    }

    public HotkeyBuilder WithTrigger(string trigger)
    {
        _trigger = trigger;
        return this;
    }

    public HotkeyBuilder WithAction(string action)
    {
        _action = action;
        return this;
    }

    public HotkeyBuilder WithDescription(string? description)
    {
        _description = description;
        return this;
    }

    public HotkeyBuilder WithClock(TimeProvider clock)
    {
        _clock = clock;
        return this;
    }

    public Hotkey Build() => Hotkey.Create(_ownerOid, _trigger, _action, _description, _profileId, _clock);
}
