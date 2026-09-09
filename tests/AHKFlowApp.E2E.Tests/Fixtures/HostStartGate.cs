namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Lets one API host start at a time.
/// </summary>
/// <remarks>
/// Serilog keeps the process-wide Log.Logger it finds when Program.cs calls AddSerilog, and
/// freezes that instance the first time anything resolves ILoggerFactory. Two hosts starting
/// together can keep the same instance, and the second freeze throws
/// "The logger is already frozen."
///
/// Program.cs catches that itself, so the test never sees the message. What it sees is
/// "The entry point exited without ever building an IHost", because the host start-up gave up
/// before it produced anything.
///
/// The gate is held across host construction and the first logger resolution, because the read
/// and the freeze sit at opposite ends of host start-up.
/// </remarks>
internal static class HostStartGate
{
    private static readonly SemaphoreSlim Gate = new(1, 1);

    public static async Task RunAsync(Func<Task> start)
    {
        await Gate.WaitAsync();
        try
        {
            await start();
        }
        finally
        {
            Gate.Release();
        }
    }
}
