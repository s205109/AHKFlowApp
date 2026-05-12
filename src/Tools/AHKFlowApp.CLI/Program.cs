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
    .MinimumLevel.Is(verbose ? LogEventLevel.Information : LogEventLevel.Error)
    .Enrich.FromLogContext()
    .WriteTo.Console(
        standardErrorFromLevel: LogEventLevel.Verbose,
        outputTemplate: "{Message:lj}{NewLine}{Exception}")
    .CreateLogger();

builder.Services.AddSerilog();

builder.Services.AddSingleton<IDeviceCodePromptWriter, ConsoleErrorDeviceCodePromptWriter>();
builder.Services.AddSingleton<IAuthCachePathProvider, LocalAppDataAuthCachePathProvider>();
builder.Services.AddSingleton<IAuthTokenProvider, MsalDeviceCodeTokenProvider>();
builder.Services.AddTransient<BearerTokenHandler>();

string apiBaseUrl = builder.Configuration["ApiBaseUrl"]
    ?? throw new InvalidOperationException("Configuration value 'ApiBaseUrl' is required.");

builder.Services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler(static options =>
    {
        options.Retry.MaxRetryAttempts = 5;
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(20);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    });

builder.Services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler(static options =>
    {
        options.Retry.MaxRetryAttempts = 5;
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(20);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    });

builder.Services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
        c.BaseAddress = new Uri(apiBaseUrl))
    .AddHttpMessageHandler<BearerTokenHandler>()
    .AddStandardResilienceHandler(static options =>
    {
        options.Retry.MaxRetryAttempts = 5;
        options.AttemptTimeout.Timeout = TimeSpan.FromSeconds(20);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(90);
    });

builder.Services.AddSingleton<BinaryStdout>();
builder.Services.AddSingleton<WorkingDirectory>();

using IHost host = builder.Build();

RootCommand root = RootCli.Build(host.Services);
return await root.Parse(args).InvokeAsync();
