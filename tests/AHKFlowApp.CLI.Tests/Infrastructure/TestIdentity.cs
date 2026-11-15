namespace AHKFlowApp.CLI.Tests.Infrastructure;

// The user one CLI call signs in as. The CLI integration tests share one API host, so the
// identity travels with each request, and TestIdentityHandler sends it as X-Test-* headers.
internal sealed record TestIdentity(Guid Oid, string Email, bool WithoutScope = false);
