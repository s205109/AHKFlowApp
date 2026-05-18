# CLI binary version self-reporting fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ahkflow --version` print the git tag (e.g. `0.1.3+<sha>`) instead of the SDK fallback (`1.0.0+<sha>`), and prevent winget-breaking release-asset mutation by hardening the release workflow.

**Architecture:** Add `MinVer` to the CLI csproj so the assembly's `InformationalVersion` flows from the git tag. Extend `release-cli.yml` with a stdout-only, regex-based version-vs-tag assertion and an upload step that refuses to overwrite an existing asset. Update the winget runbook to document the new guarantee.

**Tech Stack:** .NET 10 SDK, MinVer 7.0.0, System.CommandLine 3.0 (preview), GitHub Actions, PowerShell (`pwsh`), `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-05-18-cli-binary-version-fix-design.md`

**Branch:** `feature/cli-binary-version-fix` (already created; spec is committed there)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` | Modify | Add MinVer `<PackageReference>` so the build-time assembly version reflects the git tag. |
| `.github/workflows/release-cli.yml` | Modify (verify step) | Assert `ahkflow.exe --version` prefix matches the release tag; fail the workflow otherwise. |
| `.github/workflows/release-cli.yml` | Modify (publish step) | Refuse to overwrite an already-published release asset for the same tag. |
| `docs/cli/winget-submission.md` | Modify | Document the new immutability guarantee in the "Subsequent releases" section. |

No new files. No test files (the change is purely build-tooling; verification happens via CI on a tagged commit and via a local sanity build).

**Out of plan scope:** Posting the validator reply on PR #374595 (the maintainer pastes it manually — see Task 6). Tagging and shipping v0.1.3 (a separate release event after merge).

---

## Task 1: Add MinVer to the CLI csproj

**Files:**
- Modify: `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`

- [ ] **Step 1: Add the MinVer PackageReference**

Open `src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj`. The current `<ItemGroup>` for package references (lines 13–22) looks like:

```xml
<ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" />
    <PackageReference Include="Microsoft.Extensions.Http.Resilience" />
    <PackageReference Include="Microsoft.Identity.Client" />
    <PackageReference Include="Microsoft.Identity.Client.Extensions.Msal" />
    <PackageReference Include="Serilog.Extensions.Hosting" />
    <PackageReference Include="Serilog.Settings.Configuration" />
    <PackageReference Include="Serilog.Sinks.Console" />
    <PackageReference Include="System.CommandLine" />
</ItemGroup>
```

Insert the `MinVer` reference in alphabetical position (between `Microsoft.Identity.Client.Extensions.Msal` and `Serilog.Extensions.Hosting`). The result should be:

```xml
<ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" />
    <PackageReference Include="Microsoft.Extensions.Http.Resilience" />
    <PackageReference Include="Microsoft.Identity.Client" />
    <PackageReference Include="Microsoft.Identity.Client.Extensions.Msal" />
    <PackageReference Include="MinVer">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Serilog.Extensions.Hosting" />
    <PackageReference Include="Serilog.Settings.Configuration" />
    <PackageReference Include="Serilog.Sinks.Console" />
    <PackageReference Include="System.CommandLine" />
</ItemGroup>
```

Notes:
- No `Version=` attribute. Central Package Management (`Directory.Packages.props`) already pins `MinVer 7.0.0`.
- `Directory.Build.props` already sets `<MinVerTagPrefix>v</MinVerTagPrefix>` solution-wide, so the `v0.1.2`/`v0.1.3` tags are recognised.
- The `IncludeAssets` / `PrivateAssets` shape mirrors what `AHKFlowApp.API.csproj:17-20` and `AHKFlowApp.UI.Blazor.csproj` already use, so MinVer's build-only assets do not flow transitively to consumers.

- [ ] **Step 2: Restore and build the CLI to make sure nothing breaks**

Run from the repository root:

```powershell
dotnet restore src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj
dotnet build src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj --configuration Release --no-restore
```

Expected: build succeeds, no new warnings. MinVer prints a line like `MinVer: Calculated version 0.1.3-alpha.0.NN+<sha>` to the build log because HEAD is past `v0.1.2` on the feature branch (untagged → height-suffixed pre-release).

- [ ] **Step 3: Smoke-check the produced `--version` output**

Run:

```powershell
dotnet run --project src/Tools/AHKFlowApp.CLI --configuration Release --no-build -- --version
```

Expected output (the exact suffix varies — what matters is the prefix is **not** `1.0.0`):

```
0.1.3-alpha.0.NN+<commit-sha>
```

If the output still starts with `1.0.0`, MinVer is not actually being applied — most commonly because `<PrivateAssets>all</PrivateAssets>` was omitted (which sometimes blocks the targets), or because the build is using a cached `obj/` from before the edit. Run `dotnet clean src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj` and rebuild. Do not proceed to Step 4 until the version line is non-`1.0.0`.

- [ ] **Step 4: Confirm the CLI test suite still passes**

Run:

```powershell
dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release --verbosity normal
```

Expected: all CLI tests pass. (None assert on version strings, so MinVer should not break anything. If a test does fail with a version-related diff, the test is asserting on assembly metadata it shouldn't — investigate and fix the test before continuing.)

- [ ] **Step 5: Commit**

```powershell
git add src/Tools/AHKFlowApp.CLI/AHKFlowApp.CLI.csproj
git commit -m "feat(cli): wire MinVer so --version reflects the git tag

The CLI csproj was the only publishable project missing the MinVer
package reference, so AssemblyInformationalVersion fell back to the
SDK default of 1.0.0+sha. With MinVer in place, a tagged build now
produces e.g. 0.1.3+sha and the binary self-report aligns with the
winget manifest's PackageVersion."
```

---

## Task 2: Add the version-vs-tag assertion to `release-cli.yml`

**Files:**
- Modify: `.github/workflows/release-cli.yml` (the `Verify package` step, immediately after the existing `--help` check at lines 167–170)

- [ ] **Step 1: Locate the insertion point**

Open `.github/workflows/release-cli.yml`. The end of the `Verify package` step currently looks like (lines 167–170):

```yaml
          & (Join-Path $extractPath "ahkflow.exe") --help
          if ($LASTEXITCODE -ne 0) {
              throw "ahkflow.exe --help failed with exit code $LASTEXITCODE."
          }
```

Immediately after that closing `}` and before the next `- uses: actions/upload-artifact@v4` line, the new block goes in.

- [ ] **Step 2: Add the version assertion block**

Append the following lines so the `Verify package` step's `run: |` body ends with both the existing `--help` block and the new `--version` block:

```yaml
          $expectedVersion = $env:RELEASE_TAG.TrimStart("v")

          # Capture stdout only. The CLI configures Serilog to write to stderr,
          # so any future startup banner on stderr must not be allowed to push
          # the version line past our parser (which is why we do NOT use 2>&1).
          $versionOutput = & (Join-Path $extractPath "ahkflow.exe") --version
          if ($LASTEXITCODE -ne 0) {
              throw "ahkflow.exe --version failed with exit code $LASTEXITCODE."
          }

          $versionText = ($versionOutput -join "`n")

          # Match the first SemVer token in the output, with optional +build
          # or -prerelease tail. Robust to extra lines and to System.CommandLine
          # changing its surrounding wording.
          if ($versionText -notmatch '\b(\d+\.\d+\.\d+)(?:[+-][^\s]*)?\b') {
              throw "Could not find a SemVer token in --version output. Raw output: '$versionText'"
          }

          $actualVersion = $Matches[1]
          if ($actualVersion -ne $expectedVersion) {
              throw "Version mismatch. Tag: $expectedVersion. Binary reports: $actualVersion. Expected the binary's InformationalVersion to match the tag (sans 'v')."
          }
```

Mind the indentation: the lines must sit at the same column as the existing `& (Join-Path $extractPath "ahkflow.exe") --help` line (10 spaces of leading whitespace under `run: |`).

- [ ] **Step 3: Syntax-check the YAML**

Run a YAML parse check to catch indentation slips:

```powershell
$content = Get-Content .github/workflows/release-cli.yml -Raw
try {
    $content | ConvertFrom-Yaml | Out-Null
    Write-Host "YAML parses OK."
} catch {
    Write-Host "YAML parse failed: $_"
}
```

If `ConvertFrom-Yaml` is not available (Windows PowerShell without `powershell-yaml`), fall back to:

```powershell
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release-cli.yml','r',encoding='utf-8').read()); print('YAML parses OK.')"
```

Expected: `YAML parses OK.` Any other output means the indentation drifted — re-open the file and align with the surrounding step.

- [ ] **Step 4: Dry-run the PowerShell logic against a known-good string**

In a `pwsh` session at the repo root, paste:

```powershell
$expectedVersion = "0.1.3"
$versionText = "0.1.3+abcdef1234"
if ($versionText -notmatch '\b(\d+\.\d+\.\d+)(?:[+-][^\s]*)?\b') {
    throw "Regex did not match"
}
$actualVersion = $Matches[1]
if ($actualVersion -ne $expectedVersion) { throw "mismatch: $actualVersion vs $expectedVersion" }
Write-Host "OK: $actualVersion"
```

Expected: `OK: 0.1.3`. Then repeat with a deliberately broken string to confirm the gate fails loudly:

```powershell
$expectedVersion = "0.1.3"
$versionText = "1.0.0+abcdef1234"
if ($versionText -notmatch '\b(\d+\.\d+\.\d+)(?:[+-][^\s]*)?\b') { throw "Regex did not match" }
$actualVersion = $Matches[1]
if ($actualVersion -ne $expectedVersion) { throw "mismatch: $actualVersion vs $expectedVersion" }
```

Expected: throws `mismatch: 1.0.0 vs 0.1.3`.

- [ ] **Step 5: Commit**

```powershell
git add .github/workflows/release-cli.yml
git commit -m "ci(release): assert ahkflow --version matches the release tag

Extend the Verify package step in release-cli.yml with a stdout-only,
regex-based check that the binary's reported SemVer matches RELEASE_TAG
(minus the leading v). Hard-fails the workflow before the asset is
uploaded, so a regression in MinVer wiring can never ship to winget
silently again."
```

---

## Task 3: Enforce release-asset immutability in `release-cli.yml`

**Files:**
- Modify: `.github/workflows/release-cli.yml` (the `Publish GitHub Release asset` step's `else` branch, lines 191–196)

- [ ] **Step 1: Locate the existing upload branch**

The current `Publish GitHub Release asset` step ends with (lines 184–196):

```yaml
          gh release view $env:RELEASE_TAG 2>$null
          if ($LASTEXITCODE -ne 0) {
              gh release create $env:RELEASE_TAG $zipPath --verify-tag --title $env:RELEASE_TAG --notes "AHKFlow CLI Windows x64 release."
              if ($LASTEXITCODE -ne 0) {
                  throw "gh release create failed with exit code $LASTEXITCODE."
              }
          }
          else {
              gh release upload $env:RELEASE_TAG $zipPath --clobber
              if ($LASTEXITCODE -ne 0) {
                  throw "gh release upload failed with exit code $LASTEXITCODE."
              }
          }
```

- [ ] **Step 2: Replace the `else` branch with an immutability check**

Change only the `else { ... }` branch. The `if` branch (release does not yet exist → create + upload in one shot) stays untouched. The new `else` branch:

```yaml
          else {
              $assetName = Split-Path $zipPath -Leaf
              $existingAssets = gh release view $env:RELEASE_TAG --json assets --jq ".assets[].name" 2>$null

              if ($existingAssets -split "`n" -contains $assetName) {
                  throw "Release asset '$assetName' is already published for tag $($env:RELEASE_TAG). Treating release assets as immutable. To ship a new build, cut a new tag."
              }

              gh release upload $env:RELEASE_TAG $zipPath
              if ($LASTEXITCODE -ne 0) {
                  throw "gh release upload failed with exit code $LASTEXITCODE."
              }
          }
```

Key changes from the current code:
- `--clobber` is gone.
- A list of existing asset names is fetched via `gh release view --json assets --jq ".assets[].name"`.
- If our asset name (`ahkflow-win-x64.zip`) is already in that list, the step throws — winget consumers rely on the SHA256 being stable for the lifetime of the tag.
- If the asset is not yet present (e.g., a release was created manually with notes but no binary, or a previous workflow upload step failed before completing), the upload proceeds normally.

- [ ] **Step 3: Re-check the YAML parses**

Repeat Step 3 from Task 2 — `ConvertFrom-Yaml` (or `python -c "import yaml; ..."`) on the file. Expected: `YAML parses OK.`

- [ ] **Step 4: Dry-run the asset-existence check against a real release**

This step only validates the `gh` invocation shape — it does **not** mutate anything. In a `pwsh` session with `gh` authenticated:

```powershell
$tag = "v0.1.2"
gh release view $tag --json assets --jq ".assets[].name"
```

Expected: a single line `ahkflow-win-x64.zip` is printed (the v0.1.2 release we already published). Confirms the JSON path and jq filter both work.

Then verify the negative case against a fictitious tag:

```powershell
gh release view "v0.0.0-does-not-exist" --json assets --jq ".assets[].name" 2>$null
```

Expected: empty output, non-zero exit. In the workflow, `2>$null` suppresses the error message; the `-contains` comparison against an empty `$existingAssets` returns false; control falls through to the upload. That's the intended behaviour for a fresh tag.

- [ ] **Step 5: Commit**

```powershell
git add .github/workflows/release-cli.yml
git commit -m "ci(release): refuse to overwrite an existing release asset

The previous --clobber semantics broke the immutability promise that
docs/cli/winget-submission.md (line 29) makes to downstream winget
consumers: a re-run of the workflow on an existing tag would silently
mutate the asset's SHA256 and invalidate any winget manifest already
submitted or merged. Replace --clobber with an explicit existence
check that hard-fails the workflow. Recovery from a partial-upload
state remains possible via 'gh release delete-asset' + re-run."
```

---

## Task 4: Document the new guarantee in the winget runbook

**Files:**
- Modify: `docs/cli/winget-submission.md` (between lines 160 and 162)

- [ ] **Step 1: Insert the new paragraph**

Open `docs/cli/winget-submission.md`. The relevant region is currently (lines 158–162):

```markdown
wingetcreate new-version --urls $zipUrl AHKFlow.CLI
```

`wingetcreate` clones your fork, generates manifests at `manifests/a/AHKFlow/CLI/0.1.2/` reusing metadata from the prior version, and recomputes the SHA256. Re-run steps 3–7 above.

**Versioning rule:** `PackageVersion` always equals the git tag with the `v` stripped (`v1.2.3` → `1.2.3`).
```

Insert a new paragraph between the `wingetcreate clones your fork…` paragraph (line 160) and the `**Versioning rule:**` line (line 162). After the change the region reads:

```markdown
wingetcreate new-version --urls $zipUrl AHKFlow.CLI
```

`wingetcreate` clones your fork, generates manifests at `manifests/a/AHKFlow/CLI/0.1.2/` reusing metadata from the prior version, and recomputes the SHA256. Re-run steps 3–7 above.

The `release-cli.yml` workflow asserts that the binary's reported version matches the tag before uploading, and refuses to overwrite an existing release asset for the same tag. So the SHA256 you compute against the published asset is stable for the lifetime of the tag — re-running the workflow on the same tag will fail rather than mutate the asset.

**Versioning rule:** `PackageVersion` always equals the git tag with the `v` stripped (`v1.2.3` → `1.2.3`).
```

- [ ] **Step 2: Lint the markdown**

Run a quick sanity check — the file should still render cleanly:

```powershell
$lines = Get-Content docs/cli/winget-submission.md
"Lines: $($lines.Length); Headings: $((Select-String -Path docs/cli/winget-submission.md -Pattern '^#+ ').Count)"
```

Expected: line count grew by ~2 (the new paragraph + blank line), heading count unchanged. If the heading count changed, an accidental `#` got into the new paragraph — fix.

- [ ] **Step 3: Commit**

```powershell
git add docs/cli/winget-submission.md
git commit -m "docs(cli): document release-asset immutability in winget runbook

The Subsequent releases section now states that the workflow refuses
to overwrite an existing asset for the same tag, so the SHA256
computed against the published zip is stable for the lifetime of the
tag. This matches the new release-cli.yml behaviour."
```

---

## Task 5: Push the branch and open the PR

**Files:** none (git/GitHub-only)

- [ ] **Step 1: Verify the branch state**

```powershell
git status
git log feature/cli-binary-version-fix --oneline -10
```

Expected: clean working tree (apart from the `.lscache` untracked noise present at session start), and the branch shows — top to bottom — Task 4 commit, Task 3 commit, Task 2 commit, Task 1 commit, the two spec commits (`c208a07`, `1440c88`), then `6a4f85f` (origin/main HEAD).

- [ ] **Step 2: Confirm build and tests one more time before pushing**

```powershell
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: build succeeds, all tests pass. If either fails, fix the cause and amend the relevant task's commit (do **not** add a noise "fix typo" commit on top — keep the four implementation commits clean).

- [ ] **Step 3: Push the branch**

```powershell
git push -u origin feature/cli-binary-version-fix
```

Expected: branch tracks `origin/feature/cli-binary-version-fix`.

- [ ] **Step 4: Open the PR**

```powershell
gh pr create --base main --head feature/cli-binary-version-fix `
    --title "fix(cli): wire MinVer and enforce release-asset immutability" `
    --body @"
## Summary
- Wires MinVer into ``AHKFlowApp.CLI.csproj`` so ``ahkflow --version`` reflects the git tag instead of the SDK fallback ``1.0.0+sha``. Addresses winget-pkgs PR #374595 validator finding.
- Adds a stdout-only, regex-based version-vs-tag assertion to the ``Verify package`` step in ``release-cli.yml`` so a future regression cannot ship to winget silently.
- Drops ``--clobber`` from the ``Publish GitHub Release asset`` step and replaces it with an explicit asset-existence check that hard-fails on re-run. Closes the gap where re-running the workflow on an existing tag would mutate a SHA256 already merged into winget.
- Updates ``docs/cli/winget-submission.md`` to document the new immutability guarantee.

## Spec
``docs/superpowers/specs/2026-05-18-cli-binary-version-fix-design.md``

## Test plan
- [ ] CI: build + test pass on the PR.
- [ ] After merge, tag ``v0.1.3`` and trigger the release workflow. The ``Verify package`` step asserts the binary reports ``0.1.3`` before upload; the ``Publish`` step uploads on first run.
- [ ] Re-run the release workflow on the same tag (``workflow_dispatch`` with ``v0.1.3``). Confirm it fails at the upload step with the immutability error.
- [ ] Submit a fresh winget PR for v0.1.3 per ``docs/cli/winget-submission.md``. Validator's ``ahkflow --version`` smoke check should report ``0.1.3+<sha>``.
"@
```

Expected: `gh` prints the PR URL. Capture it for the next step.

---

## Task 6: Post the validator reply on winget-pkgs PR #374595

**Files:** none (out-of-tree, posted manually in the browser)

This task is **not automated** — the maintainer pastes the reply by hand because the PR lives in a third-party repository and we want a human to read the validator's latest state before responding.

- [ ] **Step 1: Confirm no new comments landed since the reply was drafted**

Open `https://github.com/microsoft/winget-pkgs/pull/374595` in a browser and skim recent activity. If the validator posted anything after `comment-4480496773` that changes the picture (e.g., they auto-closed, requested something else), pause and reassess.

- [ ] **Step 2: Paste the reply**

Use the exact text from the spec's "Part A — validator reply" section (`docs/superpowers/specs/2026-05-18-cli-binary-version-fix-design.md`). For convenience, the verbatim text:

> Thanks for catching this, @stephengillie.
>
> The `1.0.0+<sha>` shown by `ahkflow --version` is a build-tooling artifact — our CLI project is missing the MinVer wiring that the rest of our solution uses, so the assembly's `InformationalVersion` falls back to the SDK default of `1.0.0` plus the source-revision commit SHA. The manifest's `PackageVersion: 0.1.2` is the authoritative version, and ARP / `winget list` reflect it correctly (`DisplayVersion: 0.1.2` as you showed).
>
> A `DisplayVersion` field in the manifest would just restate `PackageVersion`, so I'd prefer to fix it at the source: add MinVer to the CLI project so the binary self-reports the tag. That ships in **v0.1.3** as a follow-up submission; the underlying bits in this v0.1.2 PR are otherwise correct and install/upgrade behaviors aren't affected by the cosmetic mismatch.
>
> Happy to defer the merge if you'd rather see the corrected binary first — let me know.

- [ ] **Step 3: No commit needed**

Posting a GitHub comment leaves no local repo state. The PR for this branch (Task 5) is the only thing CI cares about.

---

## Definition of done

- [ ] All four implementation tasks committed on `feature/cli-binary-version-fix`.
- [ ] Local `dotnet build` + `dotnet test` pass after Task 1.
- [ ] Local `ahkflow --version` smoke (Task 1 Step 3) shows a non-`1.0.0` prefix.
- [ ] YAML parse check passes after Tasks 2 and 3.
- [ ] PR opened (Task 5) and CI green.
- [ ] Validator reply posted on PR #374595 (Task 6).

The next deliverable after this PR merges is cutting tag `v0.1.3` and running the release workflow — out of scope for this plan, but the spec's Verification section is the script to follow.
