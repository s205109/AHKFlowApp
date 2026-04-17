using AHKFlowApp.Application.Abstractions;
using NSubstitute;

namespace AHKFlowApp.Application.Tests.Hotstrings;

internal static class CurrentUserHelper
{
    public static ICurrentUser For(Guid? oid)
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(oid);
        return u;
    }
}
