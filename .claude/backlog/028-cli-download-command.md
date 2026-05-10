# 028 - CLI download command

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: CLI

## Summary

Provide a CLI command to download the generated `.ahk` script for a profile via the API.

## User story

As a power user, I want to download scripts via the CLI so that I can automate updates across machines.

## Acceptance criteria

- [x] `ahkflow download ahk --profile <name>` downloads the script.
- [x] `ahkflow download zip` downloads a zip of all the user's profile scripts to cwd (or `-o`).
- [x] CLI supports choosing an output path or printing to stdout.
- [x] Authentication is handled consistently (see 012).
- [x] Unit tests for CLI download command argument handling and output behavior.
- [x] Integration tests validate download behavior against a test API (including headers and file content).

## Out of scope

- Downloading artifacts other than per-profile `.ahk` and the all-profiles zip (e.g., compiled `.exe`, signed bundles).

## Notes / dependencies

- Depends on 027.
- `IProfilesApiClient` registration + impl moved to item 018. Remaining scope: register `IDownloadsApiClient`, implement `DownloadCommand` with `--profile` resolution.

---

**Completed:** 2026-05-10 (PR #116)
