namespace AHKFlowApp.Domain.Entities;

public sealed class HotstringProfile
{
    private HotstringProfile() { }

    public Guid HotstringId { get; private set; }
    public Guid ProfileId { get; private set; }

    public static HotstringProfile Create(Guid hotstringId, Guid profileId) =>
        new() { HotstringId = hotstringId, ProfileId = profileId };
}
