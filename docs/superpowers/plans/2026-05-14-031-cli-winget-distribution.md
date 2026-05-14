# CLI Winget Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Submit `AHKFlow.CLI` to the `microsoft/winget-pkgs` community repository so Windows users can install the existing v0.1.1 `ahkflow.exe` via `winget install AHKFlow.CLI`.

**Architecture:** No runtime, build, or release-pipeline changes. The Winget package wraps the already-published `ahkflow-win-x64.zip` from the v0.1.1 GitHub Release. Deliverables are three YAML manifests submitted as a PR to an external repo, plus two repo doc updates and one new backlog item.

**Tech Stack:** `wingetcreate` (Microsoft tool), `winget` client (for validate/install), PowerShell, GitHub CLI, GitHub PAT with `public_repo` scope.

**Design reference:** `docs/superpowers/specs/2026-05-14-031-cli-winget-distribution-design.md`

---

## File Structure

Create:

- `.claude/backlog/031-cli-winget-distribution.md` — backlog item, follows `000-backlog-item-template.md` structure.
- `docs/cli/winget-submission.md` — repeatable submission runbook.

Modify:

- `docs/cli/windows-install.md` — add a "Install via Winget (recommended)" section at the top; retain the zip flow as fallback.

External (not in this repo):

- Three YAML manifests (`AHKFlow.CLI.installer.yaml`, `AHKFlow.CLI.locale.en-US.yaml`, `AHKFlow.CLI.yaml`) submitted as a PR to `microsoft/winget-pkgs` under `manifests/a/AHKFlow/CLI/0.1.1/`.

No CLI source changes. No `release-cli.yml` changes. No `publish-cli.ps1` changes.

---

## Task 1: Add Backlog Item

**Files:**
- Create: `.claude/backlog/031-cli-winget-distribution.md`

- [ ] **Step 1: Write the backlog item** using `000-backlog-item-template.md` as the template.

Required content:

- **Metadata:** Epic = CLI distribution. Type = Feature. Interfaces = CLI. Depends on 030.
- **Summary:** Publish `AHKFlow.CLI` to the Winget community repo for v0.1.1.
- **User story:** "As a Windows user, I want to run `winget install AHKFlow.CLI` so I can install the CLI without downloading a zip or editing PATH."
- **Acceptance criteria:**
  - [ ] Three Winget manifests (installer/locale/version) authored for v0.1.1 with correct SHA256 of `ahkflow-win-x64.zip`.
  - [ ] `winget validate <manifest-dir>` exits 0 locally.
  - [ ] `winget install --manifest <manifest-dir>` succeeds on a clean Windows user profile and exposes `ahkflow` on PATH.
  - [ ] `ahkflow login`, `ahkflow hotstring list`, `ahkflow logout` succeed against prod from the winget-installed binary, no `AHKFLOW_*` overrides.
  - [ ] PR opened against `microsoft/winget-pkgs` and merged.
  - [ ] `winget install AHKFlow.CLI` (no `--manifest`) installs from the community feed after merge.
  - [ ] `winget uninstall AHKFlow.CLI` removes the binary and the PATH symlink cleanly.
  - [ ] `docs/cli/windows-install.md` recommends Winget as the default install path; zip path retained as fallback.
  - [ ] `docs/cli/winget-submission.md` documents the submission steps for future versions.
- **Out of scope:** CI automation (item 032), code signing, MSIX, auto-update, macOS/Linux.
- **Notes / dependencies:** Submission targets the existing v0.1.1 GitHub Release; no rebuild. Fallback PackageIdentifier if moderators reject `AHKFlow.CLI`: `Segocom.AHKFlowCLI`. License pulled from existing root `LICENSE` (MIT).

---

## Task 2: Author Winget Manifests

**Files (external):**
- `manifests/a/AHKFlow/CLI/0.1.1/AHKFlow.CLI.installer.yaml`
- `manifests/a/AHKFlow/CLI/0.1.1/AHKFlow.CLI.locale.en-US.yaml`
- `manifests/a/AHKFlow/CLI/0.1.1/AHKFlow.CLI.yaml`

- [ ] **Step 1: Compute installer SHA256**

```powershell
$zipUrl = "https://github.com/<owner>/AHKFlowApp/releases/download/v0.1.1/ahkflow-win-x64.zip"
$tmp = New-TemporaryFile
Invoke-WebRequest -Uri $zipUrl -OutFile $tmp.FullName
Get-FileHash -Algorithm SHA256 $tmp.FullName
```

- [ ] **Step 2: Install wingetcreate**

```powershell
winget install --id Microsoft.WingetCreate --exact
```

- [ ] **Step 3: Generate the manifest set**

Fork `microsoft/winget-pkgs` first (via `gh repo fork microsoft/winget-pkgs --clone`), then:

```powershell
cd winget-pkgs
wingetcreate new $zipUrl
```

Answer the prompts using the values defined in the design doc (PackageIdentifier `AHKFlow.CLI`, Publisher `AHKFlow`, License `MIT`, etc.). The tool writes the three YAML files into `manifests/a/AHKFlow/CLI/0.1.1/`.

- [ ] **Step 4: Hand-review the generated YAML**

Confirm:
- `PackageIdentifier: AHKFlow.CLI` in all three files
- `PackageVersion: 0.1.1` in all three files
- `InstallerType: zip` and `NestedInstallerType: portable` in the installer manifest
- `NestedInstallerFiles[0].PortableCommandAlias: ahkflow`
- `InstallerSha256` matches Step 1 (case-insensitive hex)
- `License: MIT` and `LicenseUrl` points to the repo's `LICENSE` file
- `ManifestVersion` is the current Winget schema version (1.6.0 or later)

---

## Task 3: Validate Manifests Locally

- [ ] **Step 1: Schema validation**

```powershell
winget validate .\manifests\a\AHKFlow\CLI\0.1.1
```

Exit code must be 0. If it warns about missing optional fields, fill them in rather than ignoring.

- [ ] **Step 2: Local install test on a clean user profile or VM**

```powershell
winget install --manifest .\manifests\a\AHKFlow\CLI\0.1.1
```

Open a **new** shell (PATH is read at shell launch) and run:

```powershell
ahkflow --help
ahkflow login
ahkflow hotstring list
ahkflow logout
```

All four must succeed against prod with no `AHKFLOW_*` overrides set.

- [ ] **Step 3: Local uninstall test**

```powershell
winget uninstall AHKFlow.CLI
```

In a new shell, `ahkflow` must no longer resolve. Verify `%LOCALAPPDATA%\Microsoft\WinGet\Links\ahkflow.exe` is gone.

---

## Task 4: Submit Winget PR

- [ ] **Step 1: Push the manifest commit to your fork**

```powershell
cd winget-pkgs
git checkout -b ahkflow-cli-0.1.1
git add manifests/a/AHKFlow/CLI/0.1.1
git commit -m "New package: AHKFlow.CLI version 0.1.1"
git push -u origin ahkflow-cli-0.1.1
```

- [ ] **Step 2: Open the PR**

```powershell
gh pr create --repo microsoft/winget-pkgs `
    --title "New package: AHKFlow.CLI version 0.1.1" `
    --body "First-time submission. Source: https://github.com/<owner>/AHKFlowApp/releases/tag/v0.1.1"
```

Or use `wingetcreate submit --token <PAT> .\manifests\a\AHKFlow\CLI\0.1.1` which automates fork-clone-push-PR in one step.

- [ ] **Step 3: Address moderator feedback**

Common requests: publisher identity proof, license clarification, tag adjustments. Update the YAMLs in the fork, push again — the PR updates in place.

**If `AHKFlow` is rejected as a publisher,** rename the manifest directory to `manifests/s/Segocom/AHKFlowCLI/0.1.1/`, change `PackageIdentifier` to `Segocom.AHKFlowCLI` in all three files, force-push, and update the PR title.

- [ ] **Step 4: Post-merge verification**

After the moderator merges, wait ~15–60 min for the package index to refresh, then on a different clean profile:

```powershell
winget search AHKFlow.CLI
winget install AHKFlow.CLI    # no --manifest
ahkflow --help
winget uninstall AHKFlow.CLI
```

If `PackageIdentifier` was renamed in Step 3, use `Segocom.AHKFlowCLI` here instead.

---

## Task 5: Update Repo Documentation

**Files:**
- Modify: `docs/cli/windows-install.md`
- Create: `docs/cli/winget-submission.md`

- [ ] **Step 1: Update `windows-install.md`**

Insert a new section immediately after the `# Install AHKFlow CLI on Windows` heading, **before** the existing `## Install steps`:

```markdown
## Install via Winget (recommended)

```powershell
winget install AHKFlow.CLI
```

Open a new terminal and confirm:

```powershell
ahkflow --help
```

> Note: on first launch, Windows SmartScreen may warn because the binary is unsigned. Click **More info** → **Run anyway**.

## Manual zip install (fallback)
```

Then rename the existing `## Install steps` heading to `### Steps` (under the new "Manual zip install" parent), keep the rest as-is. The zip flow stays documented as the fallback for restricted environments.

- [ ] **Step 2: Write `docs/cli/winget-submission.md`**

Sections:

1. **Prerequisites** — `wingetcreate` installed, `gh` authenticated, GitHub PAT with `public_repo` scope, a clean Windows VM or user profile for smoke-testing.
2. **Submitting a new version** — the 4-step flow from Tasks 2-4 condensed into a runbook. Key command: `wingetcreate new-version --urls <new-installer-url> AHKFlow.CLI` for releases after the first.
3. **Manifest review checklist** — the same checklist from Task 2 Step 4.
4. **Moderator feedback loop** — how to amend the PR by editing manifests in the fork and pushing.
5. **Recovering from a bad submission** — if a release zip is re-uploaded (changing SHA256), submit a new manifest version pointing at the new URL; never edit the merged manifest in place.
6. **Versioning rule** — Winget manifest `PackageVersion` must equal the git tag without the `v` prefix (e.g. tag `v0.1.2` → `PackageVersion: 0.1.2`).

---

## Task 6: Close Out Backlog Item

- [ ] **Step 1: Tick all acceptance criteria** in `.claude/backlog/031-cli-winget-distribution.md`.

- [ ] **Step 2: Add the completion footer** following the convention used in 030:

```markdown
---

**Completed:** 2026-MM-DD (v0.1.1 published to Winget community repo; `winget install AHKFlow.CLI` smoke-tested on clean Windows profile).

Follow-up: CI automation tracked in backlog item 032.
```

- [ ] **Step 3: Open follow-up backlog item 032** (CI automation for Winget submissions) — outline only, do not implement. Reference `michidk/winget-releaser` as the likely tool.

---

## Verification

End-to-end on a clean Windows profile after the Winget PR merges:

1. `winget search AHKFlow.CLI` returns the package.
2. `winget install AHKFlow.CLI` (no `--manifest`) installs from the community feed.
3. New shell: `ahkflow --help`, `ahkflow login`, `ahkflow hotstring list`, `ahkflow logout` all succeed against prod with no `AHKFLOW_*` overrides.
4. `winget uninstall AHKFlow.CLI` removes the symlink; `ahkflow` no longer resolves in a new shell.
5. `docs/cli/windows-install.md` shows Winget as the recommended path; zip flow remains documented as fallback.

---

## Mapping to Backlog Criteria

- Manifest authoring + SHA256 → Task 2.
- Local validate + install → Task 3.
- PR submission + moderator round-trip → Task 4.
- `winget install` from community feed + production smoke → Task 4 Step 4.
- Docs update → Task 5.
- Submission runbook → Task 5 Step 2.
- Backlog closure → Task 6.
