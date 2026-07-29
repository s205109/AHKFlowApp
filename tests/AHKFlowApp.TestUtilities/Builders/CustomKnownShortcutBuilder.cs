using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class CustomKnownShortcutBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _key = "K";
    private bool _ctrl = true;
    private bool _alt;
    private bool _shift;
    private bool _win;
    private string _usedBy = "Visual Studio";
    private ShortcutProtection _protection = ShortcutProtection.Unknown;
    private ShortcutScope _scope = ShortcutScope.Foreground;
    private string _does = "do something";
    private TimeProvider _clock = TimeProvider.System;

    public CustomKnownShortcutBuilder ForOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }

    public CustomKnownShortcutBuilder WithCombination(
        string key, bool ctrl = false, bool alt = false, bool shift = false, bool win = false)
    {
        _key = key; _ctrl = ctrl; _alt = alt; _shift = shift; _win = win;
        return this;
    }

    public CustomKnownShortcutBuilder UsedBy(string usedBy) { _usedBy = usedBy; return this; }

    public CustomKnownShortcutBuilder WithProtection(ShortcutProtection protection)
    {
        _protection = protection;
        return this;
    }

    public CustomKnownShortcutBuilder WithScope(ShortcutScope scope) { _scope = scope; return this; }

    public CustomKnownShortcutBuilder Does(string does) { _does = does; return this; }

    public CustomKnownShortcutBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public CustomKnownShortcut Build() => CustomKnownShortcut.Create(
        _ownerOid, _key, _ctrl, _alt, _shift, _win, _usedBy, _protection, _scope, _does, _clock);
}
