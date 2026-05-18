# CLI binary version self-reporting — design

**Status:** Approved (brainstorming, 2026-05-18)
**Related:** backlog [031](../../.claude/backlog/031-cli-winget-distribution.md), spec [2026-05-14-031-cli-winget-distribution-design.md](2026-05-14-031-cli-winget-distribution-design.md)
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
- Any change to `wingetcreate` flow or the winget submission runbook beyond a one-line clarification.
- Adding a `DisplayVersion` field to the manifest — it would just restate `PackageVersion`; the source-of-truth fix is in the binary.
- Source Link / `Microsoft.SourceLink.GitHub` integration. The SDK's `SourceRevisionId` already produces the `+sha` suffix we want.
- Touching API or Blazor projects — they already have MinVer wired.

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

Three files change. Net additions ≈ 15 lines.

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
$versionOutput = & (Join-Path $extractPath "ahkflow.exe") --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ahkflow.exe --version failed with exit code $LASTEXITCODE."
}

$actualVersion = ($versionOutput | Select-Object -First 1).Trim().Split("+")[0]
if ($actualVersion -ne $expectedVersion) {
    throw "Version mismatch. Tag: $expectedVersion. Binary reports: $actualVersion. Expected the binary's InformationalVersion to match the tag (sans 'v')."
}
```

Rationale:
- Splits on `+` so the SDK's source-revision-id (everything after `+`) does not break the comparison; the prefix is what must match.
- Trims `v` from the tag to mirror the manifest's `PackageVersion` convention.
- Hard-fails the workflow — same severity as the existing `appsettings.json` checks in the same step.
- Runs against the extracted zip, not the raw publish directory, so the verified bytes are what users receive.

**B3. `docs/cli/winget-submission.md` — one-line runbook addition**

In the "Subsequent releases (v0.1.2 and later)" section, insert between the paragraph that follows the `wingetcreate new-version` snippet ("`wingetcreate` clones your fork…") and the "**Versioning rule:**" line:

> The `release-cli.yml` workflow asserts that the binary's reported version matches the tag before publishing the release asset, so by the time you reach this step the SHA256 is pinned to a correctly-versioned binary.

## Verification

Once Part B lands and `v0.1.3` is tagged + the workflow runs:

1. The `Verify package` step asserts `ahkflow.exe --version` starts with `0.1.3` — otherwise the workflow fails before publishing.
2. After the workflow publishes the release asset, run locally:
   ```powershell
   $tag = "v0.1.3"
   Invoke-WebRequest "https://github.com/<owner>/AHKFlowApp/releases/download/$tag/ahkflow-win-x64.zip" -OutFile ahkflow.zip
   Expand-Archive ahkflow.zip -DestinationPath .\ahkflow-extract
   .\ahkflow-extract\ahkflow.exe --version  # expect: 0.1.3+<sha>
   ```
3. Submit the v0.1.3 winget PR per the runbook. The validator's manual `ahkflow --version` check should now report `0.1.3+<sha>`.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| MinVer requires deep git history. | `release-cli.yml`'s checkout already uses `fetch-depth: 0`. Confirmed before design. |
| Local `dotnet run` after merge shows e.g. `0.1.3-alpha.0.1+<sha>` on untagged commits. | Expected MinVer behavior. Fine for development; the gate only runs in the release workflow. |
| `System.CommandLine` could change how `--version` parses `AssemblyInformationalVersion` in a future major. | The gate splits on `+` defensively. If the format ever changes more substantively, the gate will fail loudly, which is what we want. |
| Validator declines to merge v0.1.2 and demands a corrected binary first. | The reply explicitly offers the defer-and-resubmit path. If they take it, we cut v0.1.3, withdraw v0.1.2, submit fresh. Outcome difference is one merge cycle. |

## Unresolved questions

None at design time. Open during implementation:

- Backlog item — assign 032? Defer.
- Patch-level (0.1.3) vs minor bump (0.2.0)? Patch — purely cosmetic fix, no behavior change.
