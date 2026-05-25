using System.ComponentModel;
using System.Diagnostics;

namespace AHKFlowApp.Launcher;

internal static class Program
{
    private const string DefaultApiProfile = "LocalDB SQL";
    private const string DefaultUiProfile = "http";
    private const int ReadinessAttempts = 120;
    private static readonly TimeSpan ReadinessDelay = TimeSpan.FromMilliseconds(500);

    public static async Task<int> Main()
    {
        string rootDirectory = FindRepositoryRoot();
        string apiProfile = Environment.GetEnvironmentVariable("AHKFLOW_API_PROFILE") ?? DefaultApiProfile;
        string uiProfile = Environment.GetEnvironmentVariable("AHKFLOW_UI_PROFILE") ?? DefaultUiProfile;
        IReadOnlyList<ProjectLaunch> launches = LauncherPlan.Create(apiProfile, uiProfile);

        using CancellationTokenSource shutdown = new();
        List<Process> processes = [];

        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            shutdown.Cancel();
        };

        Task? browserLaunches = null;

        try
        {
            foreach (ProjectLaunch launch in launches)
            {
                processes.Add(StartProject(rootDirectory, launch));
            }

            Console.WriteLine("AHKFlowApp is starting.");
            Console.WriteLine($"API profile: {apiProfile}");
            Console.WriteLine($"UI profile: {uiProfile}");
            Console.WriteLine($"API: {LauncherPlan.ApiUrl}");
            Console.WriteLine($"UI:  {LauncherPlan.FrontendUrl}");
            Console.WriteLine("Opening the UI in the browser when it is ready.");
            Console.WriteLine("Press Ctrl+C to stop both projects.");

            browserLaunches = OpenBrowsersWhenReadyAsync(launches, shutdown.Token);
            int exitCode = await WaitForFirstExitAsync(processes, shutdown.Token);
            return exitCode;
        }
        finally
        {
            shutdown.Cancel();
            if (browserLaunches is not null)
            {
                await IgnoreCancellationAsync(browserLaunches);
            }

            foreach (Process process in processes)
            {
                StopProcess(process);
            }
        }
    }

    private static string FindRepositoryRoot()
    {
        return SearchParents(Directory.GetCurrentDirectory())
            ?? SearchParents(AppContext.BaseDirectory)
            ?? throw new InvalidOperationException("Could not locate the repository root.");
    }

    private static string? SearchParents(string startDirectory)
    {
        string directory = startDirectory;
        while (!File.Exists(Path.Combine(directory, "AHKFlowApp.slnx")))
        {
            DirectoryInfo? parent = Directory.GetParent(directory);
            if (parent is null)
            {
                return null;
            }

            directory = parent.FullName;
        }

        return directory;
    }

    private static Process StartProject(string rootDirectory, ProjectLaunch launch)
    {
        ProcessStartInfo startInfo = new("dotnet")
        {
            WorkingDirectory = rootDirectory,
            UseShellExecute = false
        };

        startInfo.ArgumentList.Add("run");
        startInfo.ArgumentList.Add("--project");
        startInfo.ArgumentList.Add(launch.ProjectPath);
        startInfo.ArgumentList.Add("--launch-profile");
        startInfo.ArgumentList.Add(launch.LaunchProfile);

        Process process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start {launch.Name} project.");

        Console.WriteLine($"{launch.Name} process started with PID {process.Id}.");
        return process;
    }

    private static async Task OpenBrowsersWhenReadyAsync(
        IReadOnlyList<ProjectLaunch> launches,
        CancellationToken cancellationToken)
    {
        using HttpClient httpClient = new();
        Task[] browserTasks = launches
            .Select(launch => OpenBrowserWhenReadyAsync(httpClient, launch, cancellationToken))
            .ToArray();

        await Task.WhenAll(browserTasks);
    }

    private static async Task OpenBrowserWhenReadyAsync(
        HttpClient httpClient,
        ProjectLaunch launch,
        CancellationToken cancellationToken)
    {
        if (launch.BrowserUrl is null)
        {
            return;
        }

        bool isReady = await WaitForUrlAsync(httpClient, launch.ReadyUrl, cancellationToken);
        if (!isReady && !cancellationToken.IsCancellationRequested)
        {
            Console.WriteLine($"{launch.Name} did not become ready. Opening {launch.BrowserUrl} anyway.");
        }

        if (!cancellationToken.IsCancellationRequested)
        {
            OpenBrowser(launch.BrowserUrl);
        }
    }

    private static async Task<bool> WaitForUrlAsync(
        HttpClient httpClient,
        string url,
        CancellationToken cancellationToken)
    {
        for (int attempt = 0; attempt < ReadinessAttempts; attempt++)
        {
            try
            {
                using HttpResponseMessage response = await httpClient.GetAsync(url, cancellationToken);
                if ((int)response.StatusCode < 500)
                {
                    return true;
                }
            }
            catch (HttpRequestException)
            {
            }

            await Task.Delay(ReadinessDelay, cancellationToken);
        }

        return false;
    }

    private static void OpenBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url)
            {
                UseShellExecute = true
            });
        }
        catch (Win32Exception exception)
        {
            Console.WriteLine($"Could not open {url}: {exception.Message}");
        }
        catch (InvalidOperationException exception)
        {
            Console.WriteLine($"Could not open {url}: {exception.Message}");
        }
    }

    private static async Task<int> WaitForFirstExitAsync(
        IReadOnlyList<Process> processes,
        CancellationToken cancellationToken)
    {
        Task[] waitTasks = processes.Select(process => process.WaitForExitAsync(cancellationToken)).ToArray();

        try
        {
            await Task.WhenAny(waitTasks);
        }
        catch (OperationCanceledException)
        {
            return 0;
        }

        Process? exitedProcess = processes.FirstOrDefault(process => process.HasExited);
        return exitedProcess?.ExitCode ?? 0;
    }

    private static void StopProcess(Process process)
    {
        if (process.HasExited)
        {
            return;
        }

        try
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
        }
        catch (InvalidOperationException)
        {
        }
    }

    private static async Task IgnoreCancellationAsync(Task task)
    {
        try
        {
            await task;
        }
        catch (OperationCanceledException)
        {
        }
    }
}
