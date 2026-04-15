using System.Diagnostics;

namespace AHKFlowApp.API;

/// <summary>
/// Development helper that starts the SQL Server Docker container
/// when the AHKFLOW_START_DOCKER_SQL environment variable is set to "true".
/// Used by the "https + Docker SQL (Recommended)" launch profile.
/// </summary>
internal static class DevDockerSqlServer
{
    internal static void EnsureStarted(string contentRootPath)
    {
        string? composeDir = FindComposeDirectory(contentRootPath);
        if (composeDir is null)
        {
            Console.WriteLine("[DevDockerSqlServer] docker-compose.yml not found. Cannot start SQL Server container.");
            return;
        }

        // Stop the API container if running from a previous 'docker compose up'.
        // While this process blocks, Kestrel is not yet listening — a stale container on
        // port 5602 would cause the Blazor resolver to pick the wrong base URL for the session.
        Console.WriteLine("[DevDockerSqlServer] Stopping API container (if running) to avoid port conflict...");
        RunCommand(composeDir, "docker", "compose stop ahkflowapp-api");

        Console.WriteLine($"[DevDockerSqlServer] Starting SQL Server Docker container from {composeDir}...");
        int exitCode = RunCommand(composeDir, "docker", "compose up sqlserver -d --wait");

        if (exitCode == 0)
        {
            Console.WriteLine("[DevDockerSqlServer] SQL Server Docker container is ready.");
        }
        else
        {
            Console.Error.WriteLine($"[DevDockerSqlServer] Failed to start SQL Server Docker container (exit code: {exitCode}).");
        }
    }

    private static int RunCommand(string workingDirectory, string fileName, string arguments)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null)
            {
                Console.WriteLine($"[Docker] {e.Data}");
            }
        };

        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null)
            {
                Console.WriteLine($"[Docker] {e.Data}");
            }
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();

        return process.ExitCode;
    }

    private static string? FindComposeDirectory(string startingDirectory)
    {
        string? dir = startingDirectory;
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir, "docker-compose.yml")))
            {
                return dir;
            }

            dir = Directory.GetParent(dir)?.FullName;
        }

        return null;
    }
}
