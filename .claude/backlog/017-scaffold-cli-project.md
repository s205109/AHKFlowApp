# 017 - Scaffold CLI project

## Metadata

- **Epic**: Foundation
- **Type**: Feature
- **Interfaces**: CLI

## Summary

Create the `src/Tools/AHKFlowApp.CLI` console application project, wiring the API HttpClient, command argument parsing, and the `--profile` argument used by all CLI commands.

## User story

As a developer, I want a CLI project scaffold so that CLI feature items (hotstring management, script download) have a consistent foundation to build on.

## Acceptance criteria

- [x] `src/Tools/AHKFlowApp.CLI` project created and added to the solution.
- [ ] API HttpClient registered and configured from `appsettings.json` (base address, `.AddStandardResilienceHandler()`). — deferred to backlog 028; client interfaces (`IDownloadsApiClient`, `IProfilesApiClient`) exist, registrations land with their concrete impls.
- [x] Command-line argument parsing wired (System.CommandLine).
- [ ] `--profile <name>` argument available as shared plumbing for all commands. — deferred to backlog 028; `--profile` belongs to `DownloadCommand` and is added there.
- [x] Authentication flow stubbed and ready for integration in 012.
- [x] `dotnet run -- --help` prints help text listing available commands.
- [x] CLI project added to CI/CD build and test pipeline.

**Completed:** 2026-05-08 (PR #114) — scaffold-only; deferred ACs above are wired in PR for backlog 028.

## Out of scope

- Actual command implementations (see 018, 028).
- Full authentication implementation (see 012).

## Notes / dependencies

- Depends on 003.
- Required before any CLI command items (018, 028).
