namespace AHKFlowApp.Domain.Entities;

public sealed class HotkeyCategory
{
    private HotkeyCategory() { }

    public Guid HotkeyId { get; private set; }
    public Hotkey Hotkey { get; private set; } = null!;

    public Guid CategoryId { get; private set; }
    public Category Category { get; private set; } = null!;

    public static HotkeyCategory Create(Guid hotkeyId, Guid categoryId) => new()
    {
        HotkeyId = hotkeyId,
        CategoryId = categoryId,
    };
}
