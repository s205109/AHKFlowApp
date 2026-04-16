namespace AHKFlowApp.Application.Abstractions;

public interface ICurrentUser
{
    Guid? Oid { get; }
    string? Email { get; }
    string? Name { get; }
    bool IsAuthenticated { get; }
}
