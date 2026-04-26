# Prerequisites

What you need on a fresh checkout before running AHKFlowApp locally.

## Required

- **[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)** — all projects target `net10.0`.
- **Git** — for cloning and the symlink-aware checkout below.
- **Docker** — Docker Desktop (Windows / macOS) or Docker Engine (Linux). Used by the recommended `Docker SQL` launch profile and by the full `docker compose up` stack.

## Windows-specific

The repo uses symlinks so a single set of AI-tool config files is reachable from multiple tools. Without these two settings, the symlinks won't materialize on clone.

- **Windows Developer Mode** enabled — lets non-admin users create symlinks. Settings → For developers → Developer Mode = On.
- **`git config core.symlinks true`** — set per-repo or globally. Default on Windows is `false`.

After cloning, run the symlink setup once:

```powershell
.\scripts\setup-copilot-symlinks.ps1
```

## Optional

- **SQL Server LocalDB** — included with Visual Studio. Alternative to Docker SQL via the `LocalDB SQL` launch profile.
- **Visual Studio 2022+** — for IDE debugging via the launch profiles in `src/Backend/AHKFlowApp.API/Properties/launchSettings.json`. Not required if you use `dotnet run` from the CLI.

## Once installed

See [README](../../README.md#local-development) for "Run locally" options.

## Deploying to Azure?

Prerequisites for the Azure deploy path (Azure CLI, GitHub CLI, optional sqlcmd) are listed in [docs/deployment/getting-started.md](../deployment/getting-started.md). `scripts/deploy.ps1` checks them and fails fast with install hints if anything is missing.
