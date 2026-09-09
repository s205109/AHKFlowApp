using Xunit;

namespace AHKFlowApp.E2E.Tests;

/// <summary>
/// The one collection that never runs beside another.
/// </summary>
/// <remarks>
/// ApiFactoryTests writes a process-wide environment variable and puts the old value back. Any
/// stack reading that variable at the same moment would take the wrong server. xUnit runs every
/// parallel collection to completion before it starts a collection marked this way, so these
/// tests run last and on their own.
/// </remarks>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ExclusiveTestCollection
{
    public const string Name = "E2E-Exclusive";
}
