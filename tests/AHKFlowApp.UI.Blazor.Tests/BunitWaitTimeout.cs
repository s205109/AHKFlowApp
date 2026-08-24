using System.Runtime.CompilerServices;
using Bunit;

namespace AHKFlowApp.UI.Blazor.Tests;

/// <summary>
/// Sets the wait timeout for every bUnit "WaitFor" call in this test assembly.
/// </summary>
/// <remarks>
/// bUnit's own default is one second. That budget is too small on a loaded machine, and two page
/// tests failed on it in CI on branches that changed no compiled code (backlog item 114).
///
/// The waits themselves are fast. Measured on 2026-08-24 under code coverage, with 24 busy
/// processes on a 16-core machine, the slowest wait in the suite took 937 ms. Every other wait
/// stayed under 225 ms. So one second is not a budget for the assertion. It is a budget for the
/// whole machine, and a stall of one second is normal on a shared CI runner.
///
/// Ten seconds gives about ten times the slowest measured wait. A passing test does not get
/// slower, because a wait returns as soon as the render arrives. Only a test that really fails
/// pays the full ten seconds.
///
/// A module initializer runs once, before the first test, so no test class has to opt in.
/// <c>BunitWaitTimeoutTests</c> proves that it ran.
/// </remarks>
internal static class BunitWaitTimeout
{
    /// <summary>The timeout every bUnit wait in this assembly uses.</summary>
    internal static readonly TimeSpan Value = TimeSpan.FromSeconds(10);

    [ModuleInitializer]
    internal static void Apply() => BunitContext.DefaultWaitTimeout = Value;
}
