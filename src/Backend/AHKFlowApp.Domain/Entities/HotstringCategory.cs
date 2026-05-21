namespace AHKFlowApp.Domain.Entities;

public sealed class HotstringCategory
{
    private HotstringCategory() { }

    public Guid HotstringId { get; private set; }
    public Hotstring Hotstring { get; private set; } = null!;

    public Guid CategoryId { get; private set; }
    public Category Category { get; private set; } = null!;

    public static HotstringCategory Create(Guid hotstringId, Guid categoryId) => new()
    {
        HotstringId = hotstringId,
        CategoryId = categoryId,
    };
}
