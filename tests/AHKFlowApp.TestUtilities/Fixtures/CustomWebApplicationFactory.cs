using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Auth;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class CustomWebApplicationFactory(
    SqlContainerFixture sqlFixture,
    bool useHeaderTestAuth = true) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("Auth:UseTestProvider", "false");

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

            if (useHeaderTestAuth)
            {
                services.AddSingleton(new TestUserBuilder());
                services
                    .AddAuthentication(defaultScheme: "Test")
                    .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
            }
        });
    }

    public HttpClient CreateAuthenticatedClient(Action<TestUserBuilder>? configure = null)
    {
        var testUser = new TestUserBuilder();
        configure?.Invoke(testUser);

        HttpClient client = CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-Auth", "true");
        client.DefaultRequestHeaders.Add("X-Test-Oid", testUser.DefaultOid.ToString());
        client.DefaultRequestHeaders.Add("X-Test-Email", testUser.DefaultEmail);
        client.DefaultRequestHeaders.Add("X-Test-Name", testUser.DefaultName);

        if (testUser.DefaultScope is null)
            client.DefaultRequestHeaders.Add("X-Test-Without-Scope", "true");
        else
            client.DefaultRequestHeaders.Add("X-Test-Scope", testUser.DefaultScope);

        return client;
    }

    public WebApplicationFactory<Program> WithTestAuth(Action<TestUserBuilder>? configure = null)
    {
        TestUserBuilder testUser = new TestUserBuilder().AuthenticateByDefault();
        configure?.Invoke(testUser);

        return WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<TestUserBuilder>();
                services.AddSingleton(testUser);

                if (!useHeaderTestAuth)
                {
                    services.AddAuthentication(defaultScheme: "Test")
                            .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
                }
            }));
    }
}
