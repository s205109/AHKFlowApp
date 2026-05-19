# CLI binary version self-reporting — design

**Status:** Approved (brainstorming, 2026-05-18)
**Related:** backlog [031](../../../.claude/backlog/031-cli-winget-distribution.md), spec [2026-05-14-031-cli-winget-distribution-design.md](2026-05-14-031-cli-winget-distribution-design.md)
**Trigger:** [winget-pkgs PR #374595, comment 4480496773](https://github.com/microsoft/winget-pkgs/pull/374595#issuecomment-4480496773)

## Problem

The v0.1.2 winget submission ships a binary whose self-reported version diverges from the manifest's `PackageVersion`:

| Source | Value |
|---|---|
| `ahkflow --version` | `1.0.0+d25b6c93acb8e774c3021c1667809a5aeae6fe7d` |
| winget manifest `PackageVersion` | `0.1.2` |
| ARP `DisplayVersion` (from manifest) | `0.1.2` |

The Microsoft validator flagged this on PR #374595 and asked whether the manifest should carry an explicit `DisplayVersion`. The mismatch is cosmetic — install/upgrade behavior is unaffected, and `winget list` / ARP show the correct version — but it looks unprofessional and undermines `--version` as a debugging aid.

## Root cause

`AHKFlowApp.CLI.csproj` is the only publishable project in the solution missing a `MinVer` `<PackageReference>`. `Directory.Packages.props` pins `MinVer 7.0.0` and `Directory.Build.props` sets `<MinVerTagPrefix>v</MinVerTagPrefix>`, but those are inert without the package reference. As a result:

- `AssemblyVersion` falls back to the SDK default `1.0.0.0`.
- `AssemblyInformationalVersion` falls back to `1.0.0+<source-revision-id>` — the `+sha` is appended by the .NET SDK property `IncludeSourceRevisionInInformationalVersion` (default `true`).
- `System.CommandLine`'s built-in `--version` handler reads `AssemblyInformationalVersion`, so users see `1.0.0+<sha>`.

The winget `PackageVersion` is entered manually via `wingetcreate` from the git tag with the leading `v` stripped — an independent code path, hence the divergence.

`AHKFlowApp.API.csproj` and `AHKFlowApp.UI.Blazor.csproj` already reference MinVer with the correct `IncludeAssets` envelope and produce tag-accurate versions; only the CLI is broken.

## Outcome

1. **v0.1.2 winget PR:** a clear validator reply lands so the existing PR proceeds to merge without re-uploading the release asset.
2. **v0.1.3:** the CLI binary self-reports the tag (e.g. `0.1.3+<sha>`), matching the manifest's `PackageVersion`.
3. **Going forward:** a CI gate in `release-cli.yml` hard-fails any release whose binary version doesn't match the tag, so this regression cannot ship silently again.

## Out of scope

- Re-uploading the v0.1.2 release asset (violates the immutability rule in `docs/cli/winget-submission.md`).
- Closing or withdrawing PR #374595.
- Any `wingetcreate` flow changes; the runbook addition is the only documentation change.
- Adding a `DisplayVersion` field to the manifest — it would just restate `PackageVersion`; the source-of-truth fix is in the binary.
- Source Link / `Microsoft.SourceLink.GitHub` integration. The SDK's `SourceRevisionId` already produces the `+sha` suffix we want.
- Touching API or Blazor projects — they already have MinVer wired.
- Adding an immutability check on the API / Blazor release pipelines. The winget contract is CLI-specific; if the other pipelines grow a similar promise we'll extend then, not pre-emptively.

## Approach

Two deliverables, ordered:

### Part A — validator reply (now)

A single comment on PR #374595, posted manually by the maintainer (not via `gh pr comment`). Reply text:

> Thanks for catching this, @stephengillie.
>
> The `1.0.0+<sha>` shown by `ahkflow --version` is a build-tooling artifact — our CLI project is missing the MinVer wiring that the rest of our solution uses, so the assembly's `InformationalVersion` falls back to the SDK default of `1.0.0` plus the source-revision commit SHA. The manifest's `PackageVersion: 0.1.2` is the authoritative version, and ARP / `winget list` reflect it correctly (`DisplayVersion: 0.1.2` as you showed).
>
> A `DisplayVersion` field in the manifest would just restate `PackageVersion`, so I'd prefer to fix it at the source: add MinVer to the CLI project so the binary self-reports the tag. That ships in **v0.1.3** as a follow-up submission; the underlying bits in this v0.1.2 PR are otherwise correct and install/upgrade behaviors aren't affected by the cosmetic mismatch.
>
> Happy to defer the merge if you'd rather see the corrected binary first — let me know.

### Part B — code & CI changes for v0.1.3

Four touches. Net additions ≈ 30 lines across three files.

**B1. `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`**

Add MinVer to the existing `<ItemGroup>` of package references, mirroring `AHKFlowApp.API.csproj`:

```xml
<PackageReference Include="MinVer">
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  <PrivateAssets>all</PrivateAssets>
</PackageReference>
```

No version attribute (Central Package Management). No other csproj changes.

**B2. `.github/workflows/release-cli.yml` — extend the "Verify package" step**

Append to the existing PowerShell block in the `package` job's verify step, after the current `ahkflow.exe --help` invocation:

```powershell
$expectedVersion = $env:RELEASE_TAG.TrimStart("v")

# Capture stdout only — the CLI's Serilog logger writes to stderr, and any
# future startup warning on stderr would push the version line past
# `Select-Object -First 1` if we merged streams with 2>&1.
$versionOutput = & (Join-Path $extractPath "ahkflow.exe") --version
if ($LASTEXITCODE -ne 0) {
    throw "ahkflow.exe --version failed with exit code $LASTEXITCODE."
}

$versionText = ($versionOutput -join "`n")

# Match the first SemVer token in the output, with optional `+build` or
# `-prerelease` suffix. Robust to extra banner/diagnostic lines and to
# `System.CommandLine` changing its surrounding wording.
if ($versionText -notmatch '\b(\d+\.\d+\.\d+)(?:[+-][^\s]*)?\b') {
    throw "Could not find a SemVer token in --version output. Raw output: '$versionText'"
}

$actualVersion = $Matches[1]
if ($actualVersion -ne $expectedVersion) {
    throw "Version mismatch. Tag: $expectedVersion. Binary reports: $actualVersion. Expected the binary's InformationalVersion to match the tag (sans 'v')."
}
```

Rationale:
- Reads stdout only. The CLI configures Serilog to write to stderr (`Program.cs`), so merging streams with `2>&1` would let a future warning shift the version line.
- Regex extracts the SemVer core (`MAJOR.MINOR.PATCH`) anywhere in the output, ignoring any `+sha` suffix or `-prerelease` tail. The prefix is what must match.
- Trims `v` from the tag to mirror the manifest's `PackageVersion` convention.
- Hard-fails the workflow — same severity as the existing `appsettings.json` checks in the same step.
- Runs against the extracted zip, not the raw publish directory, so the verified bytes are what users receive.

**B3. `.github/workflows/release-cli.yml` — enforce asset immutability on upload**

The current upload logic uses `gh release upload --clobber`, which will silently overwrite an existing asset for the same tag. That contradicts the immutability promise the winget runbook depends on (`docs/cli/winget-submission.md` line 29: "Treat the GitHub Release asset as immutable once submitted — re-uploading the zip changes the SHA256 and breaks installs."). A re-run of the release workflow on an existing tag would change the SHA256 of an already-merged or already-submitted winget manifest.

Replace the existing "Publish GitHub Release asset" step's `else` branch:

```powershell
# OLD: gh release upload $env:RELEASE_TAG $zipPath --clobber
```

with an explicit existence check that fails the workflow if the asset is already published for this tag:

```powershell
$assetName = Split-Path $zipPath -Leaf
$existingAssets = gh release view $env:RELEASE_TAG --json assets --jq ".assets[].name" 2>$null

if ($existingAssets -split "`n" -contains $assetName) {
    throw "Release asset '$assetName' is already published for tag $($env:RELEASE_TAG). Treating release assets as immutable. To ship a new build, cut a new tag."
}

gh release upload $env:RELEASE_TAG $zipPath
if ($LASTEXITCODE -ne 0) {
    throw "gh release upload failed with exit code $LASTEXITCODE."
}
```

The `gh release create` branch (release doesn't exist yet) is unchanged. Manual recovery (force-overwrite) remains possible by deleting the asset via the GitHub UI or `gh release delete-asset` — but it's no longer the default code path.

**B4. `docs/cli/winget-submission.md` — runbook addition**

In the "Subsequent releases (v0.1.2 and later)" section, insert between the paragraph that follows the `wingetcreate new-version` snippet ("`wingetcreate` clones your fork…") and the "**Versioning rule:**" line:

> The `release-cli.yml` workflow asserts that the binary's reported version matches the tag before uploading, and refuses to overwrite an existing release asset for the same tag. So the SHA256 you compute against the published asset is stable for the lifetime of the tag — re-running the workflow on the same tag will fail rather than mutate the asset.

## Verification

Once Part B lands and `v0.1.3` is tagged + the workflow runs:

1. The `Verify package` step asserts `ahkflow.exe --version` reports `0.1.3` — otherwise the workflow fails before uploading.
2. The `Publish GitHub Release asset` step uploads the zip on the first run. On a second run for the same tag (re-triggered via `workflow_dispatch`), it fails with the immutability error — confirm by re-running once.
3. After the workflow publishes the release asset, run locally:
   ```powershell
   $tag = "v0.1.3"
   Invoke-WebRequest "https://github.com/<owner>/AHKFlowApp/releases/download/$tag/ahkflow-win-x64.zip" -OutFile ahkflow.zip
   Expand-Archive ahkflow.zip -DestinationPath .\ahkflow-extract
   .\ahkflow-extract\ahkflow.exe --version  # expect: 0.1.3+<sha>
   ```
4. Submit the v0.1.3 winget PR per the runbook. The validator's manual `ahkflow --version` check should now report `0.1.3+<sha>`.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| MinVer requires deep git history. | `release-cli.yml`'s checkout already uses `fetch-depth: 0`. Confirmed before design. |
| Local `dotnet run` after merge shows e.g. `0.1.3-alpha.0.1+<sha>` on untagged commits. | Expected MinVer behavior. Fine for development; the gate only runs in the release workflow. |
| `System.CommandLine` could change how `--version` parses `AssemblyInformationalVersion` in a future major. | The gate regex-matches the first SemVer token anywhere in stdout, ignoring surrounding wording and any `+build` / `-prerelease` tail. If the format ever changes so radically that no SemVer token is present, the gate fails loudly — which is what we want. |
| Validator declines to merge v0.1.2 and demands a corrected binary first. | The reply explicitly offers the defer-and-resubmit path. If they take it, we cut v0.1.3, withdraw v0.1.2, submit fresh. Outcome difference is one merge cycle. |
| The new immutability check blocks a legitimate retry — e.g., the workflow was re-run after a transient upload failure that did partially complete. | Operator deletes the half-uploaded asset (`gh release delete-asset`) and re-runs. Documented behavior — the gate refusing to silently mutate state is the point. |
| Stdout-only capture misses the version if `System.CommandLine` ever decides to print it to stderr. | Gate fails with "Could not find a SemVer token" rather than passing a false negative. Loud failure beats silent drift. |

## Unresolved questions

None at design time. Open during implementation:

- Backlog item — assign 032? Defer.
- Patch-level (0.1.3) vs minor bump (0.2.0)? Patch — purely cosmetic fix, no behavior change.
