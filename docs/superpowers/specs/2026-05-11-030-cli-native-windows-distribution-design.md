# 030 - CLI Native Windows Distribution Design

**Date:** 2026-05-11
**Backlog item:** `.claude/backlog/030-cli-native-windows-distribution.md`
**Status:** Ready for implementation

## Goal

Package the AHKFlow CLI as a regular Windows command-line tool that users can download from GitHub Releases, extract, add to `PATH`, and run as `ahkflow` without cloning the repository or installing the .NET SDK.

The first supported distribution is a Windows x64 zip release. Installer packaging, code signing, auto-update, NuGet global tool distribution, macOS packages, and Linux packages remain out of scope for this backlog item.

## Decisions

- **Release channel:** GitHub Releases are the user-facing distribution channel for backlog 030.
- **Release asset:** `ahkflow-win-x64.zip`.
- **Runtime:** `win-x64`.
- **Publish mode:** self-contained, single-file, compressed, no debug symbols.
- **Zip contents:** `ahkflow.exe`, `appsettings.json`, and `INSTALL.md` at the zip root.
- **Configuration:** source `src/Tools/AHKFlowApp.CLI/appsettings.json` keeps placeholder values; release automation patches only the publish output with production values.
- **Installer follow-up:** Winget is the preferred follow-up installer path after zip releases are stable.
- **Signing:** unsigned binary for this item. Document Windows SmartScreen expectations if needed after the first public release.

## Current State

The CLI project already has the correct executable identity:

- `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` sets `<AssemblyName>ahkflow</AssemblyName>`, so `dotnet publish` emits `ahkflow.exe` for Windows.
- `Program.cs` loads `appsettings.json` from `AppContext.BaseDirectory` and then `AHKFLOW_` environment variables.
- Authentication from backlog 029 uses MSAL device-code flow and stores the user token cache at `%LOCALAPPDATA%\AHKFlowApp\msal-cache.bin3`.

A local publish feasibility check succeeded with:

```powershell
dotnet publish src/Tools/AHKFlowApp.CLI --configuration Release --runtime win-x64 --self-contained true -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false --output .tmp\cli-win-x64-publish-nosymbols-check
```

That output contained only:

```text
ahkflow.exe
appsettings.json
```

`.\ahkflow.exe --help` and `.\ahkflow.exe --version` worked from the publish output.

## Release Packaging

Add `scripts/publish-cli.ps1` as the single local and CI packaging entrypoint. The script:

1. Publishes `src/Tools/AHKFlowApp.CLI` with the Windows x64 self-contained single-file settings.
2. Writes a release-only `appsettings.json` into the publish output using supplied production `ApiBaseUrl`, `ClientId`, and `TenantId`.
3. Copies `docs/cli/windows-install.md` into the package as `INSTALL.md`.
4. Creates `ahkflow-win-x64.zip` in the requested output directory.
5. Fails if `ahkflow.exe`, `appsettings.json`, or `INSTALL.md` is missing.
6. Fails if `appsettings.json` still contains placeholder URL or empty GUID values.

Production configuration values are public identifiers except the API URL is currently stored as a GitHub secret by `scripts/deploy.ps1`. The workflow should read:

- `secrets.AZURE_API_BASE_URL_PROD`
- `vars.AZURE_AD_CLIENT_ID_PROD`
- `vars.AZURE_AD_TENANT_ID_PROD`

The source `appsettings.json` remains safe to commit with placeholders. No production config file is committed.

## Release Workflow

Add `.github/workflows/release-cli.yml`.

Triggers:

- `push` to tags matching `v*`.
- `workflow_dispatch` with a required `tag` input for rebuilding or re-uploading a release asset for an existing tag.

Permissions:

- `contents: write`, because the workflow creates or updates GitHub Releases.

Workflow behavior:

1. Checkout full git history for MinVer.
2. Setup .NET from `global.json`.
3. Restore, build, and test the solution in Release.
4. Run `scripts/publish-cli.ps1` using production configuration from GitHub settings.
5. Verify the generated zip by expanding it, checking required entries, checking config values, and running `ahkflow.exe --help`.
6. Upload the zip as a workflow artifact for traceability.
7. Create the GitHub Release if it does not exist, or upload the asset with `--clobber` if it does.

## User Documentation

Add `docs/cli/windows-install.md`. The same content is copied into the release zip as `INSTALL.md`.

The install doc must explain:

- Download `ahkflow-win-x64.zip` from GitHub Releases.
- Extract to a stable folder, such as `%USERPROFILE%\Tools\ahkflow`.
- Add that folder to the user `PATH`.
- Run `ahkflow --help`, `ahkflow login`, `ahkflow hotstring list`, and `ahkflow logout`.
- Uninstall by removing the folder from `PATH` and deleting the extracted folder.
- Remove local auth state by deleting `%LOCALAPPDATA%\AHKFlowApp\msal-cache.bin3`, or the whole `%LOCALAPPDATA%\AHKFlowApp` directory if only CLI auth state exists there.
- `AHKFLOW_ApiBaseUrl`, `AHKFLOW_ClientId`, and `AHKFLOW_TenantId` remain advanced overrides for development or test environments, not normal production install steps.

## Error Handling

Release automation should fail early with clear messages when:

- Production config inputs are missing.
- `ClientId` or `TenantId` is not a non-empty GUID.
- The API URL is not absolute HTTPS.
- `dotnet publish` fails.
- Zip validation finds missing files, placeholder config, or no runnable `ahkflow.exe`.
- GitHub Release upload fails.

Runtime CLI error handling remains unchanged from backlog 029.

## Test Strategy

Automated and local validation:

- `dotnet build --configuration Release`
- `dotnet test --configuration Release --no-build`
- `pwsh -NoProfile -File .\scripts\publish-cli.ps1 -ApiBaseUrl https://example.invalid -ClientId 11111111-1111-1111-1111-111111111111 -TenantId 22222222-2222-2222-2222-222222222222 -OutputDirectory .tmp\cli-package-smoke`
- Expand `ahkflow-win-x64.zip` and verify required file names.
- Run extracted `ahkflow.exe --help`.
- Confirm extracted `appsettings.json` has injected values and no placeholders.

Manual release acceptance:

1. Create or use a `v*` tag.
2. Run or wait for `release-cli.yml`.
3. Download `ahkflow-win-x64.zip` from the GitHub Release.
4. Extract to a folder on a Windows machine.
5. Add the extracted folder to user `PATH`.
6. Run `ahkflow login`, complete device-code sign-in, run `ahkflow hotstring list`, then run `ahkflow logout`.

## Out of Scope

- macOS and Linux native packages.
- NuGet global tool distribution.
- Code signing.
- MSI/MSIX installer.
- Winget manifest submission in this item.
- Auto-update.
- Multiple install channels.
- New CLI commands or configuration profiles.

## Follow-Up

Create a later backlog item for Winget distribution after zip releases are stable. The Winget item should use the GitHub Release asset URL and release version, then decide whether code signing is required before public submission.
