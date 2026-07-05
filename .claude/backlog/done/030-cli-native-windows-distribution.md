# 030 - CLI native Windows distribution

## Metadata

- **Epic**: CLI distribution
- **Type**: Feature
- **Interfaces**: CLI, CI/CD
- **Depends on**: 017-scaffold-cli-project, 029-cli-authentication

## Summary

Package the AHKFlow CLI as a regular Windows command-line tool that users can install and run as `ahkflow` without cloning the repository or using `dotnet run`.

## User story

As a Windows user, I want to install the AHKFlow CLI and immediately run `ahkflow` commands so that I can manage hotstrings from the terminal without developer tooling.

## Acceptance criteria

- [x] CI publishes a Windows x64 self-contained `ahkflow` release artifact as a zip.
- [x] The published artifact contains an executable users can run as `ahkflow.exe`.
- [x] The published CLI includes production `ApiBaseUrl`, `ClientId`, and `TenantId` configuration so users do not need environment variables for normal use.
- [x] The zip includes minimal install instructions for adding the extracted folder to `PATH`.
- [x] `ahkflow login`, `ahkflow hotstring list`, and `ahkflow logout` work from the extracted zip against production services.
- [x] Release documentation explains the supported install path and how to uninstall or remove the local token cache.
- [x] A follow-up installer path is documented, either Winget or an MSI/MSIX installer, with the chosen direction recorded.

---

**Completed:** 2026-05-13 (v0.1.1 zip smoke-tested against prod: login, hotstring list, logout all passed without `AHKFLOW_` overrides; v0.1.0 had insufficient cold-start timeouts, fixed in v0.1.1)

Release channel: GitHub Releases with `ahkflow-win-x64.zip`.

Follow-up installer direction: Winget, after the zip release asset is stable.

## Out of scope

- macOS and Linux native packages.
- Publishing a NuGet global tool.
- Auto-update support.
- Multiple install channels in the same item.

## Notes / dependencies

- Use `dotnet publish` with a Windows runtime identifier, self-contained output, and single-file publishing unless MSAL cache behavior requires bundled files.
- Production configuration must be injected by release automation rather than committed as secrets. The Entra client ID and tenant ID are public identifiers; any future secret material must not be packaged.
- The CLI auth flow from 029 uses device-code login, so the installed executable should not need any user-specific configuration before `ahkflow login`.
- Consider a later follow-up item for `winget install AHKFlow.CLI` once the zip release is stable.
