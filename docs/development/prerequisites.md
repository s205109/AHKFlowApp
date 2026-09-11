# Prerequisites

What you need on a fresh checkout before running AHKFlowApp locally.

## Required

- **[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)** — all projects target `net10.0`.
- **Git** — for cloning and the symlink-aware checkout below.
- **Docker** — Docker Desktop (Windows / macOS) or Docker Engine (Linux). Used by the recommended `Docker SQL (Recommended)` launch profile and by the full `docker compose up` stack.

## Windows-specific

The repo uses symlinks so a single set of AI-tool config files is reachable from multiple tools. Without these two settings, the symlinks won't materialize on clone.

- **Windows Developer Mode** enabled — lets non-admin users create symlinks. Settings → For developers → Developer Mode = On.
- **`git config core.symlinks true`** — set per-repo or globally. Default on Windows is `false`.

After cloning, run the symlink setup once:

```powershell
.\scripts\agents\setup-copilot-symlinks.ps1
```

`scripts/agents/setup-cross-agent-skills.ps1` (re-run automatically by the `post-merge` hook when skills change) also bumps the Codex plugin version in `plugins/ahkflowapp/.codex-plugin/plugin.json` from a content hash and refreshes the installed Codex plugin cache via `codex plugin add ahkflowapp@ahkflowapp-local`. Codex captures available skills at session start — start a new Codex session after skill changes.

### Windows Defender exclusions

Optional. It needs an administrator, and it is worth doing before you run the tests often.

The PowerShell suites start thousands of short-lived `git` and `pwsh` processes. They also
build temporary git repositories under your temp folder. Windows Defender scans every process
start and every file write. That work competes with your editor and your browser, so the whole
machine can feel slow while a run is going.

Measured on one developer machine, the exclusions below took a full suite run from 180 seconds
to 163. Wall clock is not the main gain. The exclusions remove work from the machine, rather
than moving it somewhere else.

Run this in an **elevated** PowerShell. Change the path to your own clone:

```powershell
$repo = 'C:\Dev\AHKFlowApp'
Add-MpPreference -ExclusionPath $repo
Add-MpPreference -ExclusionPath $env:TEMP
Add-MpPreference -ExclusionProcess 'git.exe', 'pwsh.exe', 'dotnet.exe', 'MSBuild.exe'
```

Two things to watch:

- **`$env:TEMP` reads the account that runs the window.** If you elevate as a different user,
  that line excludes the wrong folder. Write your own temp path out in full instead.
- **An excluded path is not scanned at all.** Anything that lands there is not checked either.
  The temp folder is the broad one, because browsers and installers write there too. Leave that
  line out if it is more than you want, then see whether the repository path and the four
  process names are enough on their own.

To read the list, or to undo one line:

```powershell
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
Remove-MpPreference -ExclusionPath $env:TEMP
```

Reading the list also needs an elevated session.

Two more settings help on the same machine, and neither needs an administrator.

How many suites run at once is the first.
[testing-workflow.md](testing-workflow.md#powershell-script-suites) describes `-MaxParallel`
and `AHKFLOW_SUITE_MAX_PARALLEL`. More workers is not always faster: the suites wait on the
disk and on process starts, so past a point each extra worker only adds load.

A lower process priority is the second. Windows gives a child process its parent's priority
class, so one line in the terminal covers every `pwsh` and `git` the run starts:

```powershell
(Get-Process -Id $PID).PriorityClass = 'BelowNormal'
```

It applies to that terminal only, and it lasts until you close the window.

## Optional

- **SQL Server LocalDB** — included with Visual Studio. Alternative to Docker SQL via the `LocalDB SQL` launch profile.
- **Visual Studio 2022+** — for IDE debugging via the launch profiles in `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`. Not required if you use `dotnet run` from the CLI.

## Once installed

See [README](../../README.md#local-development) for "Run locally" options.

## Deploying to Azure?

Prerequisites for the Azure deploy path (Azure CLI, GitHub CLI, optional sqlcmd) are listed in [docs/deployment/getting-started.md](../deployment/getting-started.md). `scripts/deploy.ps1` checks them and fails fast with install hints if anything is missing.
