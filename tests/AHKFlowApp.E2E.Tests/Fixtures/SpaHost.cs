using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Yarp.ReverseProxy.Forwarder;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class SpaHost : IAsyncDisposable
{
    private readonly WebApplication _app;
    public string BaseUrl { get; }

    private SpaHost(WebApplication app, string baseUrl) { _app = app; BaseUrl = baseUrl; }

    public static async Task<SpaHost> StartAsync(string publishedWwwroot, HttpMessageInvoker apiInvoker, string apiBaseUrl)
    {
        WebApplicationBuilder builder = WebApplication.CreateBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddHttpForwarder();

        WebApplication app = builder.Build();
        IHttpForwarder forwarder = app.Services.GetRequiredService<IHttpForwarder>();

        // In .NET 10, blazor.boot.json no longer exists — the boot config (including
        // applicationEnvironment) is embedded inside the fingerprinted blazor.webassembly.*.js
        // and cannot be reliably overridden via the Blazor-Environment header at runtime.
        // Blazor WASM loads appsettings.json first, then appsettings.{Environment}.json on top —
        // we don't know which env Blazor will pick, so intercept ALL appsettings*.json requests
        // and inject E2E overrides so Auth:UseTestProvider=true reaches Program.cs regardless.
        app.Use(async (ctx, next) =>
        {
            string? path = ctx.Request.Path.Value;
            bool isAppSettings = path is not null
                && path.StartsWith("/appsettings", StringComparison.OrdinalIgnoreCase)
                && path.EndsWith(".json", StringComparison.OrdinalIgnoreCase);

            if (!isAppSettings) { await next(); return; }

            string basePath = Path.Combine(publishedWwwroot, "appsettings.json");
            JsonNode merged = File.Exists(basePath)
                ? JsonNode.Parse(await File.ReadAllTextAsync(basePath)) ?? new JsonObject()
                : new JsonObject();
            merged["Auth"] = new JsonObject { ["UseTestProvider"] = true };
            merged["ApiBaseUrl"] = "/";

            ctx.Response.ContentType = "application/json";
            await ctx.Response.WriteAsync(merged.ToJsonString());
        });

        app.Map("/api/{**catch-all}", async (HttpContext ctx) =>
        {
            await forwarder.SendAsync(ctx, apiBaseUrl, apiInvoker, ForwarderRequestConfig.Empty);
        });

        PhysicalFileProvider fp = new(publishedWwwroot);
        app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = fp });
        app.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = fp,
            ServeUnknownFileTypes = true,
            DefaultContentType = "application/octet-stream",
        });
        app.MapFallback(async (HttpContext ctx) =>
        {
            ctx.Response.ContentType = "text/html";
            await ctx.Response.SendFileAsync(Path.Combine(publishedWwwroot, "index.html"));
        });

        await app.StartAsync();
        string addr = app.Urls.First();
        return new SpaHost(app, addr);
    }

    public async ValueTask DisposeAsync() => await _app.DisposeAsync();
}
