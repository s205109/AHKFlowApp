using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Auth;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Web;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class CustomWebApplicationFactory(
    SqlContainerFixture sqlFixture) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Program.cs conditionally skips auth when AzureAd config is empty at startup.
            // ConfigureAppConfiguration runs too late to influence that check, so we register
            // auth directly here — M.I.W. validates TenantId/ClientId lazily on the first
            // authenticated request, not at startup.
            services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
                .AddMicrosoftIdentityWebApi(
                    _ => { },
                    o =>
                    {
                        o.TenantId = "00000000-0000-0000-0000-000000000001";
                        o.ClientId = "00000000-0000-0000-0000-000000000002";
                    });

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
