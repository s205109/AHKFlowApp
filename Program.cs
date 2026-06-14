using System.ComponentModel;
using System.Diagnostics;

namespace AHKFlowApp.Launcher;

internal static class Program
{
    private const string DefaultApiProfile = "LocalDB SQL";
    private const string DefaultUiProfile = "http";
    private const string ApiProfileEnvironmentVariable = "AHKFLOW_API_PROFILE";
    private const string UiProfileEnvironmentVariable = "AHKFLOW_UI_PROFILE";
    private const string ApiUrlEnvironmentVariable = "AHKFLOW_API_URL";
    private const string UiUrlEnvironmentVariable = "AHKFLOW_UI_URL";
    private const string WorktreeManifestRelativePath = "scripts/.env.worktree";
    private const string SolutionMarker = "AHKFlowApp.slnx";
    private const int ReadinessAttempts = 120;
    private static readonly TimeSpan s_readinessDelay = TimeSpan.FromMilliseconds(500);

    public static async Task<int> Main()
    {
        string rootDirectory = FindRepositoryRoot();
        string apiProfile = Environment.GetEnvironmentVariable(ApiProfileEnvironmentVariable) ?? DefaultApiProfile;
        string uiProfile = Environment.GetEnvironmentVariable(UiProfileEnvironmentVariable) ?? DefaultUiProfile;

        string manifestPath = Path.Combine(rootDirectory, WorktreeManifestRelativePath);
        WorktreeLocalDevManifest manifest = File.Exists(manifestPath)
            ? WorktreeLocalDevManifest.Parse(await File.ReadAllTextAsync(manifestPath))
            : WorktreeLocalDevManifest.Parse("");

        string apiUrl = Environment.GetEnvironmentVariable(ApiUrlEnvironmentVariable) ?? manifest.ApiUrl;
        string uiUrl = Environment.GetEnvironmentVariable(UiUrlEnvironmentVariable) ?? manifest.UiUrl;

        IReadOnlyList<ProjectLaunch> launches = LauncherPlan.Create(apiProfile, uiProfile, apiUrl, uiUrl);

        using CancellationTokenSource shutdown = new();
        List<Process> processes = [];
        Dictionary<string, int> pidsByName = [];

        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            shutdown.Cancel();
        };

        Task? browserLaunches = null;

        try
        {
            Console.WriteLine("AHKFlowApp is starting.");
            Console.WriteLine($"API profile: {apiProfile}");
            Console.WriteLine($"UI profile: {uiProfile}");
            Console.WriteLine($"API: {apiUrl}");
            Console.WriteLine($"UI:  {uiUrl}");
            Console.WriteLine("Starting the API first; the UI launches once the API is ready.");
            Console.WriteLine("Press Ctrl+C to stop both projects.");

            using HttpClient readinessClient = new();

            // Sequential startup: start each project, then wait for it to respond before
            // starting the next. This guarantees the UI only launches after the API is
            // serving (which now includes the Docker SQL readiness wait + EF migration).
            for (int index = 0; index < launches.Count; index++)
            {
                ProjectLaunch launch = launches[index];
                Process process = StartProject(rootDirectory, launch);
                processes.Add(process);
                pidsByName[launch.Name] = process.Id;

                bool hasNext = index < launches.Count - 1;
                if (!hasNext)
                {
                    continue;
                }

                ProjectLaunch next = launches[index + 1];
                Console.WriteLine($"Waiting for {launch.Name} to be ready before starting {next.Name}.");
                bool ready = await WaitForProjectReadyAsync(readinessClient, process, launch.ReadyUrl, shutdown.Token);
                if (shutdown.Token.IsCancellationRequested)
                {
                    break;
                }

                Console.WriteLine(ready
                    ? $"{launch.Name} is ready. Starting {next.Name}."
                    : $"{launch.Name} did not become ready in time. Starting {next.Name} anyway.");
            }

            UpdateManifestWithPids(manifestPath, pidsByName);

            Console.WriteLine("Opening the UI in the browser when it is ready.");

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

            // The children are hard-killed above, so the API's own shutdown never runs.
            // Stop the Docker SQL container here (keep the data volume) when a Docker SQL
            // profile is active. ComposeProject is the per-worktree name from the manifest,
            // or the bare base for the main checkout.
            if (apiProfile.StartsWith("Docker SQL", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"Stopping Docker SQL container (compose project '{manifest.ComposeProject}').");
                DockerSqlControl.Stop(rootDirectory, manifest.ComposeProject);
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
        while (!File.Exists(Path.Combine(directory, SolutionMarker)))
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
        startInfo.ArgumentList.Add("--");
        startInfo.ArgumentList.Add("--urls");
        startInfo.ArgumentList.Add(launch.UrlOverride);

        Process process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start {launch.Name} project.");

        Console.WriteLine($"{launch.Name} process started with PID {process.Id}.");
        return process;
    }

    private static void UpdateManifestWithPids(string manifestPath, IReadOnlyDictionary<string, int> pidsByName)
    {
        try
        {
            string existingContent = File.Exists(manifestPath) ? File.ReadAllText(manifestPath) : "";
            List<string> lines = [.. existingContent.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)];

            foreach (KeyValuePair<string, int> entry in pidsByName)
            {
                string pidKey = $"AHKFLOW_{entry.Key.ToUpperInvariant()}_PID=";
                lines.RemoveAll(line => line.StartsWith(pidKey, StringComparison.OrdinalIgnoreCase));
            }

            foreach (KeyValuePair<string, int> entry in pidsByName)
            {
                string pidKey = $"AHKFLOW_{entry.Key.ToUpperInvariant()}_PID";
                lines.Add($"{pidKey}={entry.Value}");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(manifestPath)!);
            File.WriteAllText(manifestPath, string.Join(Environment.NewLine, lines) + Environment.NewLine);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Console.WriteLine($"Warning: could not write PIDs to manifest: {ex.Message}");
        }
    }

    private static async Task OpenBrowsersWhenReadyAsync(
        IReadOnlyList<ProjectLaunch> launches,
        CancellationToken cancellationToken)
    {
        using HttpClient httpClient = new();
        Task[] browserTasks = [.. launches.Select(launch => OpenBrowserWhenReadyAsync(httpClient, launch, cancellationToken))];

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

    private static async Task<bool> WaitForProjectReadyAsync(
        HttpClient httpClient,
        Process process,
        string url,
        CancellationToken cancellationToken)
    {
        for (int attempt = 0; attempt < ReadinessAttempts; attempt++)
        {
            if (cancellationToken.IsCancellationRequested || process.HasExited)
            {
                return false;
            }

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
            catch (OperationCanceledException)
            {
                return false;
            }

            try
            {
                await Task.Delay(s_readinessDelay, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return false;
            }
        }

        return false;
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

            await Task.Delay(s_readinessDelay, cancellationToken);
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
        Task[] waitTasks = [.. processes.Select(process => process.WaitForExitAsync(cancellationToken))];

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
