# Winget submission runbook

How to publish a new AHKFlow CLI version to the `microsoft/winget-pkgs` community repository.

Manifests are not stored in this repo — they live as a PR against the external community repo, keyed by the GitHub Release tag.

## Prerequisites

- Windows machine (Win10 1809+ or Win11) with the App Installer / `winget` client.
- `wingetcreate`: `winget install --id Microsoft.WingetCreate --exact`.
- `gh` CLI authenticated with an account that has a fork of `microsoft/winget-pkgs`.
- GitHub Personal Access Token with `public_repo` scope (for `wingetcreate submit`).
- A clean Windows user profile or VM for post-merge smoke testing.

## First-time submission (v0.1.1)

### 1. Compute the installer SHA256

```powershell
$tag = "v0.1.1"
$zipUrl = "https://github.com/<owner>/AHKFlowApp/releases/download/$tag/ahkflow-win-x64.zip"

$tmp = New-TemporaryFile
Invoke-WebRequest -Uri $zipUrl -OutFile $tmp.FullName
(Get-FileHash -Algorithm SHA256 $tmp.FullName).Hash
Remove-Item $tmp.FullName
```

Record the hash. Treat the GitHub Release asset as immutable once submitted — re-uploading the zip changes the SHA256 and breaks installs.

### 2. Generate manifests

Fork `microsoft/winget-pkgs` once via `gh repo fork microsoft/winget-pkgs --clone`, then from the fork:

```powershell
wingetcreate new $zipUrl
```

Answer the prompts:

| Field | Value |
|---|---|
| PackageIdentifier | `AHKFlow.CLI` |
| PackageVersion | `0.1.1` (tag minus `v`) |
| Publisher | `AHKFlow` |
| PackageName | `AHKFlow CLI` |
| License | `MIT` |
| LicenseUrl | `https://github.com/<owner>/AHKFlowApp/blob/main/LICENSE` |
| PackageUrl | `https://github.com/<owner>/AHKFlowApp` |
| ReleaseNotesUrl | `https://github.com/<owner>/AHKFlowApp/releases/tag/v0.1.1` |
| ShortDescription | Command-line tool for managing AutoHotkey hotstrings and hotkeys. |
| Tags | `autohotkey`, `hotstring`, `cli`, `windows` |
| InstallerType | `zip` |
| NestedInstallerType | `portable` |
| NestedInstallerFiles | `ahkflow.exe` with `PortableCommandAlias: ahkflow` |
| Architecture | `x64` |
| Commands | `ahkflow` |

`Scope` is **not** supported for `InstallerType: portable`; omit it (Winget validation will warn if present).

Three YAML files land in `manifests/a/AHKFlow/CLI/0.1.1/`:

- `AHKFlow.CLI.installer.yaml`
- `AHKFlow.CLI.locale.en-US.yaml`
- `AHKFlow.CLI.yaml`

### 3. Manifest review checklist

Open each YAML and verify:

- [ ] `PackageIdentifier: AHKFlow.CLI` in all three files.
- [ ] `PackageVersion: 0.1.1` in all three files (tag without `v`).
- [ ] `InstallerType: zip`, `NestedInstallerType: portable` in the installer manifest.
- [ ] `NestedInstallerFiles[0].RelativeFilePath: ahkflow.exe`.
- [ ] `NestedInstallerFiles[0].PortableCommandAlias: ahkflow`.
- [ ] `InstallerSha256` matches the value from step 1 (case-insensitive).
- [ ] `InstallerUrl` points at the immutable tag-pinned release asset, not `latest`.
- [ ] `License: MIT`, `LicenseUrl` points to the `LICENSE` file at the tag.
- [ ] `ManifestVersion` is the schema version supported by the installed `winget` (1.6.0 or later).

### 4. Validate locally

```powershell
winget validate .\manifests\a\AHKFlow\CLI\0.1.1
```

Must exit 0. Fix any warnings rather than ignoring them — moderators run the same check.

### 5. Smoke test on a clean profile

```powershell
winget install --manifest .\manifests\a\AHKFlow\CLI\0.1.1
```

Open a **new** shell (Winget Links are read at shell launch) and run:

```powershell
ahkflow --help
ahkflow login
ahkflow hotstring list
ahkflow logout
```

All four must succeed against production with no `AHKFLOW_*` environment overrides.

Uninstall test:

```powershell
winget uninstall AHKFlow.CLI
```

In a new shell, `ahkflow` must no longer resolve. Verify `%LOCALAPPDATA%\Microsoft\WinGet\Links\ahkflow.exe` is gone.

### 6. Submit the PR

Easiest path — let `wingetcreate` push and open the PR:

```powershell
wingetcreate submit --token <PAT> .\manifests\a\AHKFlow\CLI\0.1.1
```

Manual path:

```powershell
cd winget-pkgs
git checkout -b ahkflow-cli-0.1.1
git add manifests/a/AHKFlow/CLI/0.1.1
git commit -m "New package: AHKFlow.CLI version 0.1.1"
git push -u origin ahkflow-cli-0.1.1

gh pr create --repo microsoft/winget-pkgs `
    --title "New package: AHKFlow.CLI version 0.1.1" `
    --body "First-time submission. Source: https://github.com/<owner>/AHKFlowApp/releases/tag/v0.1.1"
```

### 7. Post-merge verification

Wait 15-60 min for the package index to refresh after the moderator merges. On a different clean profile:

```powershell
winget search AHKFlow.CLI
winget install AHKFlow.CLI    # no --manifest
ahkflow --help
winget uninstall AHKFlow.CLI
```

If any step fails, do not retry — investigate. The most common cause is SHA256 mismatch from a re-uploaded release asset; the fix is a new manifest version, not editing the merged one.

## Subsequent releases (v0.1.2 and later)

After tagging a new release and confirming the GitHub Release zip is published:

```powershell
$tag = "v0.1.2"
$zipUrl = "https://github.com/<owner>/AHKFlowApp/releases/download/$tag/ahkflow-win-x64.zip"

wingetcreate new-version --urls $zipUrl AHKFlow.CLI
```

`wingetcreate` clones your fork, generates manifests at `manifests/a/AHKFlow/CLI/0.1.2/` reusing metadata from the prior version, and recomputes the SHA256. Re-run steps 3–7 above.

The `release-cli.yml` workflow asserts that the binary's reported version matches the tag before uploading, and refuses to overwrite an existing release asset for the same tag. So the SHA256 you compute against the published asset is stable for the lifetime of the tag — re-running the workflow on the same tag will fail rather than mutate the asset.

**Versioning rule:** `PackageVersion` always equals the git tag with the `v` stripped (`v1.2.3` → `1.2.3`).

## Moderator feedback loop

Moderators may request changes. Push commits to the same fork branch — the PR updates in place:

```powershell
cd winget-pkgs
git checkout ahkflow-cli-0.1.1
# edit manifests
git add manifests/a/AHKFlow/CLI/0.1.1
git commit -m "Address moderator feedback"
git push
```

### If `AHKFlow` publisher is rejected

If the unverified `AHKFlow` publisher namespace is rejected:

1. Rename directory: `manifests/a/AHKFlow/CLI/0.1.1/` → `manifests/s/Segocom/AHKFlowCLI/0.1.1/`.
2. Change `PackageIdentifier` to `Segocom.AHKFlowCLI` in all three YAMLs.
3. Update `Publisher` to `Segocom` in the locale manifest.
4. Force-push the branch, update the PR title.
5. After merge, update `docs/cli/windows-install.md` to use the new identifier.

## Recovering from a bad submission

If a release zip is re-uploaded after manifests are merged (SHA256 changes, all installs break):

- Do not edit the merged manifest — the community feed caches by version + SHA.
- Submit a new patch version (`0.1.2` → `0.1.3`) pointing at the new asset.
- Yank nothing; users on the old version are unaffected.

If a manifest needs to be removed entirely, submit a PR that deletes the version directory and explain why in the PR body. Moderators handle these case-by-case.
