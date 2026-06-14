using System.ComponentModel;
using System.Diagnostics;

namespace AHKFlowApp.Launcher;

/// <summary>
/// Stops the Docker SQL container on launcher shutdown when a Docker SQL profile is active.
/// Uses <c>docker compose ... stop</c> (not <c>down</c>) so the named data volume — and the
/// database — survives across runs. The launcher hard-kills its child processes, so an
/// ASP.NET shutdown hook in the API never runs under this profile; the launcher is the only
/// reliable place to stop the container. Best-effort: a missing docker CLI or a non-zero exit
/// is swallowed, never thrown, so shutdown is never blocked.
/// </summary>
internal static class DockerSqlControl
{
    // Separated for testing: the exact argument list passed to 'docker'. The -f keeps the
    // compose context explicit.
    internal static IReadOnlyList<string> BuildStopArguments(string repoRoot, string composeProject) =>
        [
            "compose",
            "-f", Path.Combine(repoRoot, "docker-compose.yml"),
            "-p", composeProject,
            "stop"
        ];

    internal static void Stop(string repoRoot, string composeProject)
    {
        ProcessStartInfo startInfo = new("docker")
        {
            WorkingDirectory = repoRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        foreach (string argument in BuildStopArguments(repoRoot, composeProject))
        {
            startInfo.ArgumentList.Add(argument);
        }

        Process process;
        try
        {
            var started = Process.Start(startInfo);
            if (started is null)
            {
                return;
            }

            process = started;
        }
        catch (Win32Exception)
        {
            // docker CLI not installed / not on PATH — nothing to stop.
            return;
        }

        using (process)
        {
            // Drain both pipes so a chatty compose can't fill the OS buffer and deadlock.
            _ = process.StandardOutput.ReadToEndAsync();
            _ = process.StandardError.ReadToEndAsync();

            if (!process.WaitForExit(30000))
            {
                try { process.Kill(entireProcessTree: true); } catch { /* best effort */ }
            }
        }
    }
}
