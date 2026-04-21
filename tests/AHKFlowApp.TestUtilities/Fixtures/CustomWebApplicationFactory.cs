using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Auth;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class CustomWebApplicationFactory(
    SqlContainerFixture sqlFixture) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Microsoft.Identity.Web validates ClientId/TenantId on first request — provide
        // placeholder values so anonymous endpoints work without real Entra credentials.
        builder.ConfigureAppConfiguration(config =>
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AzureAd:TenantId"] = "00000000-0000-0000-0000-000000000001",
                ["AzureAd:ClientId"] = "00000000-0000-0000-0000-000000000002"
            }));

        builder.ConfigureServices(services =>
        {
            var descriptors = services
                .Where(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>)
                         || d.ServiceType == typeof(AppDbContext))
                .ToList();

            foreach (ServiceDescriptor d in descriptors)
                services.Remove(d);

            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(sqlFixture.ConnectionString,
                    sql => sql.EnableRetryOnFailure()));
        });
    }

    public WebApplicationFactory<Program> WithTestAuth(Action<TestUserBuilder>? configure = null)
    {
        var testUser = new TestUserBuilder();
        configure?.Invoke(testUser);

        return WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
            {
                services.AddSingleton(testUser);
                services.AddAuthentication(defaultScheme: "Test")
                        .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
            }));
    }
}
