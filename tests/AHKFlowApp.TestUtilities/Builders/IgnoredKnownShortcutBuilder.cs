using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.TestUtilities.Builders;

public sealed class IgnoredKnownShortcutBuilder
{
    private Guid _ownerOid = Guid.NewGuid();
    private string _shortcutId = "windows.file-explorer";
    private string _usedBy = "Windows";
    private TimeProvider _clock = TimeProvider.System;

    public IgnoredKnownShortcutBuilder ForOwner(Guid ownerOid) { _ownerOid = ownerOid; return this; }

    public IgnoredKnownShortcutBuilder ForShortcut(string shortcutId) { _shortcutId = shortcutId; return this; }

    public IgnoredKnownShortcutBuilder UsedBy(string usedBy) { _usedBy = usedBy; return this; }

    public IgnoredKnownShortcutBuilder WithClock(TimeProvider clock) { _clock = clock; return this; }

    public IgnoredKnownShortcut Build() =>
        IgnoredKnownShortcut.Create(_ownerOid, _shortcutId, _usedBy, _clock);
}
