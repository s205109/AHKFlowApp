namespace AHKFlowApp.Domain.Entities;

public sealed class HotkeyProfile
{
    private HotkeyProfile() { }

    public Guid HotkeyId { get; private set; }
    public Guid ProfileId { get; private set; }

    public static HotkeyProfile Create(Guid hotkeyId, Guid profileId) =>
        new() { HotkeyId = hotkeyId, ProfileId = profileId };
}
