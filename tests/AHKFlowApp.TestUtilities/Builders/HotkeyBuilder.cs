using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class HotkeyBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _description = "Open Notepad";
    private string _key = "n";
    private bool _ctrl;
    private bool _alt;
    private bool _shift;
    private bool _win;
    private HotkeyAction _action = HotkeyAction.Run;
    private string _parameters = "notepad.exe";
    private bool _appliesToAllProfiles = true;
    private TimeProvider _clock = TimeProvider.System;

    public HotkeyBuilder WithOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }
    public HotkeyBuilder WithDescription(string description) { _description = description; return this; }
    public HotkeyBuilder WithKey(string key) { _key = key; return this; }
    public HotkeyBuilder WithCtrl(bool value = true) { _ctrl = value; return this; }
    public HotkeyBuilder WithAlt(bool value = true) { _alt = value; return this; }
    public HotkeyBuilder WithShift(bool value = true) { _shift = value; return this; }
    public HotkeyBuilder WithWin(bool value = true) { _win = value; return this; }
    public HotkeyBuilder WithAction(HotkeyAction action) { _action = action; return this; }
    public HotkeyBuilder WithParameters(string parameters) { _parameters = parameters; return this; }
    public HotkeyBuilder AppliesToAll(bool value = true) { _appliesToAllProfiles = value; return this; }
    public HotkeyBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public Hotkey Build() => Hotkey.Create(
        _ownerOid, _description, _key, _ctrl, _alt, _shift, _win,
        _action, _parameters, _appliesToAllProfiles, _clock);
}
