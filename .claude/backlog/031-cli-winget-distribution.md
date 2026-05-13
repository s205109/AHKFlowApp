# 031 - CLI Winget distribution

## Metadata

- **Epic**: CLI distribution
- **Type**: Feature
- **Interfaces**: CLI
- **Depends on**: 030-cli-native-windows-distribution

## Summary

Publish the AHKFlow CLI to the Windows Package Manager (`winget`) community repository so Windows users can install it with `winget install AHKFlow.CLI`. The package wraps the existing v0.1.1 GitHub Release zip — no rebuild, no new binary.

## User story

As a Windows user, I want to run `winget install AHKFlow.CLI` so that I can install the CLI without downloading a zip or editing my user PATH.

## Acceptance criteria

- [ ] Three Winget manifests (installer / locale / version) authored for v0.1.1 with the correct SHA256 of `ahkflow-win-x64.zip`.
- [ ] `winget validate <manifest-dir>` exits 0 locally.
- [ ] `winget install --manifest <manifest-dir>` succeeds on a clean Windows user profile and exposes `ahkflow` on PATH.
- [ ] `ahkflow login`, `ahkflow hotstring list`, `ahkflow logout` succeed against production from the winget-installed binary with no `AHKFLOW_*` overrides set.
- [ ] PR opened against `microsoft/winget-pkgs` and merged.
- [ ] `winget install AHKFlow.CLI` (no `--manifest`) installs from the community feed after merge.
- [ ] `winget uninstall AHKFlow.CLI` removes the binary and the PATH symlink cleanly.
- [ ] `docs/cli/windows-install.md` recommends Winget as the default install path; the zip flow is retained as fallback.
- [ ] `docs/cli/winget-submission.md` documents the submission steps so the next release can re-run them without rediscovery.

## Out of scope

- CI automation for Winget submissions (planned as backlog item 032).
- Code signing the `ahkflow.exe` binary.
- MSI / MSIX installer formats.
- Auto-update beyond what `winget upgrade` provides natively.
- macOS / Linux package managers.
- Changes to CLI command surface, runtime configuration, or auth flow.
- Changes to `release-cli.yml` or `scripts/publish-cli.ps1`.

## Notes / dependencies

- Submission targets the existing v0.1.1 GitHub Release; no rebuild.
- Manifests use `InstallerType: zip` + `NestedInstallerType: portable` so Winget handles PATH registration via its symlink directory.
- License pulled from existing root `LICENSE` (MIT, Copyright 2026 Bart Segers).
- Binary remains unsigned for v1. Windows SmartScreen will warn on first launch — document this in the install doc.
- Fallback PackageIdentifier if moderators reject the unverified `AHKFlow` publisher: `Segocom.AHKFlowCLI`. Manifest-only change, no rebuild.
- Design: `docs/superpowers/specs/2026-05-14-031-cli-winget-distribution-design.md`.
- Plan: `docs/superpowers/plans/2026-05-14-031-cli-winget-distribution.md`.
