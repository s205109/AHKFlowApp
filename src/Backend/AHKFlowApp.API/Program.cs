using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.Extensions.Diagnostics.HealthChecks;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSwaggerDocs();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>(
        name: "database",
        failureStatus: HealthStatus.Unhealthy);

WebApplication app = builder.Build();

app.UseMiddleware<GlobalExceptionMiddleware>();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseSwaggerDocs();
app.UseHttpsRedirection();

// Redirect root to Swagger UI (after HTTPS redirect so the redirect is served over HTTPS)
app.Use(async (context, next) =>
{
    if (context.Request.Path == "/")
    {
        context.Response.Redirect("/swagger");
        return;
    }
    await next(context);
});

app.UseAuthorization();
app.MapControllers();

// Plain-text infrastructure endpoint (for load balancers, k8s probes)
app.MapHealthChecks("/health");

app.Run();

public partial class Program { }
