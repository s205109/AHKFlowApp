using AHKFlowApp.TestUtilities.Fixtures;

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

    internal const string QueueWaitOperation = "QueueWait";
    internal const string GatedWorkOperation = "GatedWork";

    /// <summary>The caller a record carries when nobody named one.</summary>
    /// <remarks>
    /// A stack fixture, a test's own host, and a test's bare callback all start through this gate.
    /// A labelled default keeps an unnamed caller apart from a stack start, so a report never folds
    /// a test's host into the figure for the four stacks.
    /// </remarks>
    internal const string UnattributedCaller = "Unattributed";

    private static string Fixture => typeof(HostStartGate).FullName ?? nameof(HostStartGate);

    public static async Task RunAsync(Func<Task> start, string caller = UnattributedCaller)
    {
        // The permit is released whenever it was taken, and only then. The recorder writes a
        // step's record after the step completes, so recording the wait can throw after the wait
        // has already taken the permit. With the release outside that record, one failed write
        // closed the gate for every later host in the process. The flag is set inside the wait's
        // own action, which is the one place that knows the permit is held: a wait that throws
        // leaves it false, and nothing is released that was never taken.
        bool acquired = false;
        try
        {
            // Two records, not one. The wait belongs to the queue and the work belongs to the host,
            // and a single figure would grow with the number of callers while no host did more work.
            await TestTimingRecorder.RecordAsync(
                nameof(HostStartGate),
                Fixture,
                QueueWaitOperation,
                async () =>
                {
                    await Gate.WaitAsync();
                    acquired = true;
                },
                caller);

            await TestTimingRecorder.RecordAsync(
                nameof(HostStartGate),
                Fixture,
                GatedWorkOperation,
                start,
                caller);
        }
        finally
        {
            if (acquired)
            {
                Gate.Release();
            }
        }
    }
}
