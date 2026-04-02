using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSwaggerDocs();
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

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

app.Run();

public partial class Program { }
