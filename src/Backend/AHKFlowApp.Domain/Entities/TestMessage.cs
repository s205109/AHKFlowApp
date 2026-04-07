namespace AHKFlowApp.Domain.Entities;

public sealed class TestMessage
{
    public int Id { get; set; }
    public string Message { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
