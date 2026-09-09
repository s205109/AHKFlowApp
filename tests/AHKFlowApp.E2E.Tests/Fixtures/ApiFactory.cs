using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// One API host for one stack, on its own database.
/// </summary>
/// <remarks>
/// The discriminator names the database. Each stack passes its own, so several stacks share one
/// SQL Server and never share rows. E2ESqlServer is what keeps the container count at one.
/// </remarks>
public sealed class ApiFactory(string discriminator) : WebApplicationFactory<Program>
{
    private string? _connectionString;

    internal string ConnectionString => _connectionString
        ?? throw new InvalidOperationException("E2E API SQL connection has not been initialized.");

    public async Task StartAsync()
    {
        _connectionString = SqlTestDatabase.CreateConnectionString(
            await E2ESqlServer.GetConnectionStringAsync(), discriminator);

        await HostStartGate.RunAsync(async () =>
        {
            // Force the factory to build the host (triggers ConfigureWebHost).
            _ = Services;

            // Resolving ILoggerFactory is what runs Serilog's registration, and that is where the
            // bootstrap logger is frozen. Doing it here keeps the freeze inside the gate.
            _ = Services.GetRequiredService<ILoggerFactory>();

            using AsyncServiceScope scope = Services.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
        });
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Test");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = ConnectionString,
                // Microsoft.Identity.Web validates these on first request — provide placeholders
                ["AzureAd:TenantId"] = "00000000-0000-0000-0000-000000000001",
                ["AzureAd:ClientId"] = "00000000-0000-0000-0000-000000000002",
            });
        });
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.PostConfigure<AuthorizationOptions>(opts =>
            {
                opts.DefaultPolicy = new AuthorizationPolicyBuilder(TestAuthHandler.SchemeName)
                    .RequireAuthenticatedUser().Build();
            });
        });
    }
}
