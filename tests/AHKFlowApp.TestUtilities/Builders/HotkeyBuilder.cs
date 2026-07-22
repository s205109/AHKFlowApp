using AHKFlowApp.Application.Services;
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
    private HotkeyActionKind? _actionKind;
    private string? _text;
    private string? _sendKeysContent;
    private string? _runTarget;
    private RunTargetKind? _runTargetKind;
    private WindowOp? _windowOp;
    private string? _remapDest;
    private string? _body;
    private bool _appliesToAllProfiles = true;
    private Guid[] _profileIds = [];
    private readonly List<Guid> _categoryIds = [];
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
    public HotkeyBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    // Typed action setters. These populate the W1 columns directly, bypassing
    // LegacyHotkeyDefinitionConverter, so a test can pin one specific action kind.

    public HotkeyBuilder WithSendText(string text)
    {
        _actionKind = HotkeyActionKind.SendText; _text = text; return this;
    }

    public HotkeyBuilder WithSendKeys(string content)
    {
        _actionKind = HotkeyActionKind.SendKeys; _sendKeysContent = content; return this;
    }

    public HotkeyBuilder WithRun(string target, RunTargetKind kind = RunTargetKind.Application)
    {
        _actionKind = HotkeyActionKind.Run; _runTarget = target; _runTargetKind = kind; return this;
    }

    public HotkeyBuilder WithWindow(WindowOp op)
    {
        _actionKind = HotkeyActionKind.Window; _windowOp = op; return this;
    }

    public HotkeyBuilder WithRemap(string dest)
    {
        _actionKind = HotkeyActionKind.Remap; _remapDest = dest; return this;
    }

    public HotkeyBuilder WithDisable()
    {
        _actionKind = HotkeyActionKind.Disable; return this;
    }

    public HotkeyBuilder WithRawBody(string body)
    {
        _actionKind = HotkeyActionKind.Raw; _body = body; return this;
    }

    public HotkeyBuilder InProfile(Guid profileId)
    {
        _appliesToAllProfiles = false;
        _profileIds = [profileId];
        return this;
    }

    public HotkeyBuilder WithProfiles(params Guid[] profileIds)
    {
        _appliesToAllProfiles = false;
        _profileIds = profileIds;
        return this;
    }

    public HotkeyBuilder AppliesToAll(bool value = true)
    {
        _appliesToAllProfiles = value;
        if (value) _profileIds = [];
        return this;
    }

    public HotkeyBuilder WithCategory(Guid categoryId)
    {
        _categoryIds.Add(categoryId);
        return this;
    }

    public HotkeyBuilder WithCategories(params Guid[] categoryIds)
    {
        _categoryIds.Clear();
        _categoryIds.AddRange(categoryIds);
        return this;
    }

    public Hotkey Build()
    {
        HotkeyDefinition definition = _actionKind is HotkeyActionKind kind
            ? new HotkeyDefinition(
                Description: _description, Key: _key,
                Ctrl: _ctrl, Alt: _alt, Shift: _shift, Win: _win,
                Action: _action, Parameters: _parameters,
                AppliesToAllProfiles: _appliesToAllProfiles,
                ActionKind: kind, Text: _text, SendKeysContent: _sendKeysContent,
                RunTarget: _runTarget, RunTargetKind: _runTargetKind, WindowOp: _windowOp,
                RemapDest: _remapDest, Body: _body)
            : LegacyHotkeyDefinitionConverter.Apply(new HotkeyDefinition(
                Description: _description, Key: _key,
                Ctrl: _ctrl, Alt: _alt, Shift: _shift, Win: _win,
                Action: _action, Parameters: _parameters,
                AppliesToAllProfiles: _appliesToAllProfiles));

        var entity = Hotkey.Create(_ownerOid, definition, _clock);

        foreach (Guid pid in _profileIds)
            entity.Profiles.Add(HotkeyProfile.Create(entity.Id, pid));

        foreach (Guid cid in _categoryIds)
            entity.Categories.Add(HotkeyCategory.Create(entity.Id, cid));

        return entity;
    }
}
