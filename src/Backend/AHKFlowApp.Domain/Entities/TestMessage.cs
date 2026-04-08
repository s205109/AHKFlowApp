namespace AHKFlowApp.Domain.Entities;

public sealed class TestMessage
{
    public int Id { get; init; }
    public string Message { get; init; } = string.Empty;
    public DateTime CreatedAt { get; init; }
}
