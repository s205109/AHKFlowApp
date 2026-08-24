using Bunit;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests;

public sealed class BunitWaitTimeoutTests
{
    // The module initializer is the only thing that raises the timeout. If it stops running, the
    // suite silently returns to bUnit's one-second default and the flaky failures come back. This
    // test is the signal that it still runs.
    [Fact]
    public void ModuleInitializer_RaisesTheDefaultWaitTimeout()
    {
        BunitContext.DefaultWaitTimeout.Should().Be(BunitWaitTimeout.Value);
        BunitContext.DefaultWaitTimeout.Should().BeGreaterThan(TimeSpan.FromSeconds(1));
    }
}
