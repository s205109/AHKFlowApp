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

        app.Use(async (ctx, next) =>
        {
            await next();
            if (ctx.Request.Path.Value?.EndsWith("blazor.boot.json", StringComparison.OrdinalIgnoreCase) == true)
                ctx.Response.Headers["Blazor-Environment"] = "E2E";
        });

        app.Map("/api/{**catch-all}", async (HttpContext ctx) =>
        {
            await forwarder.SendAsync(ctx, apiBaseUrl, apiInvoker, ForwarderRequestConfig.Empty);
        });

        PhysicalFileProvider fp = new(publishedWwwroot);
        app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = fp });
        app.UseStaticFiles(new StaticFileOptions { FileProvider = fp });
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
