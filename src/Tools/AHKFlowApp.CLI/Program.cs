using System.CommandLine;
using AHKFlowApp.CLI;
using AHKFlowApp.CLI.Commands;
using AHKFlowApp.CLI.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Configuration
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: false)
    .AddEnvironmentVariables("AHKFLOW_");

builder.Services.Configure<CliOptions>(builder.Configuration);

bool verbose = args.Any(a => a == "--verbose" || a == "-v");

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Is(verbose ? LogEventLevel.Information : LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .WriteTo.Console(
        standardErrorFromLevel: LogEventLevel.Verbose,
        outputTemplate: "{Message:lj}{NewLine}{Exception}")
    .CreateLogger();

builder.Services.AddSerilog();

builder.Services.AddSingleton<IAuthTokenProvider, EnvVarAuthTokenProvider>();
builder.Services.AddTransient<BearerTokenHandler>();

string apiBaseUrl = builder.Configuration["ApiBaseUrl"]
    ?? throw new InvalidOperationException("Configuration value 'ApiBaseUrl' is required.");

builder.Services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

builder.Services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler();

// IDownloadsApiClient registration lands with backlog 028.

using IHost host = builder.Build();

RootCommand root = RootCli.Build(host.Services);
return await root.Parse(args).InvokeAsync();
