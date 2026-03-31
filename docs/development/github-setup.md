# GitHub Open Source Setup Guide for AHKFlowApp

Quick setup guide for GitHub Issues, Projects, labels, and branch protection.

---

## 1. Create Labels

Create these new labels (in addition to GitHub defaults like `bug`, `enhancement`):

```bash
gh repo set-default s205109/AHKFlowApp

# Interface labels
gh label create "api" --color "1d76db" --description "Affects API layer"
gh label create "ui" --color "5319e7" --description "Affects UI/Blazor layer"
gh label create "cli" --color "e99695" --description "Affects CLI tool"

# Epic labels (based on backlog structure) - each with distinct color
gh label create "epic: backlog setup" --color "9e6dc6" --description "Epic: Backlog setup"
gh label create "epic: initial project" --color "0052cc" --description "Epic: Initial project / solution"
gh label create "epic: foundation" --color "006b75" --description "Epic: Foundation"
gh label create "epic: versioning" --color "1f883d" --description "Epic: Versioning"
gh label create "epic: logging" --color "6e40aa" --description "Epic: Logging"
gh label create "epic: observability" --color "c5def5" --description "Epic: Observability"
gh label create "epic: ci/cd" --color "fd7e14" --description "Epic: CI/CD"
gh label create "epic: authentication" --color "d1242f" --description "Epic: Authentication and authorization"
gh label create "epic: hotstrings" --color "28a745" --description "Epic: Hotstrings"
gh label create "epic: hotkeys" --color "3fb950" --description "Epic: Hotkeys"
gh label create "epic: profiles" --color "0969da" --description "Epic: Profiles"
gh label create "epic: script generation" --color "8957e5" --description "Epic: Script generation & download"

# Workflow label
gh label create "wip" --color "fbca04" --description "Work in progress"

# List all labels
gh label list --limit 100
```

---

## 2. Branch Protection

### Initial Setup (Without Status Checks)

**Note**: Status checks require at least one GitHub Actions workflow to run first. Set up basic protection now, add status checks later.

1. Go to **Settings** → **Branches** → **Add branch ruleset**
2. Configure:

```plaintext
Ruleset name: Protect main
Enforcement status: Active
Target branches: Include default branch

Rules:
✅ Restrict deletions
✅ Require linear history
✅ Require a pull request before merging
   - Required approvals: 0
   - Dismiss stale approvals: ✅
   - Require conversation resolution: ✅
⬜ Require status checks to pass (skip for now)
✅ Block force pushes
```

### Add Status Checks (After CI Workflow Exists)

After you have a CI workflow running (e.g., from backlog item 010), return to add status checks:

1. Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    name: build
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Test
        run: dotnet test --no-build --verbosity normal
```

1. Commit and push to `main`:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add CI workflow"
git push origin main
```

1. Wait for workflow to complete in **Actions** tab

1. Edit your branch ruleset:
   - Go to **Settings** → **Branches** → **Rulesets** → **Protect main**
   - ✅ Check **Require status checks to pass**
   - Select `build` from the status check list
   - ✅ Check **Require branches to be up to date**
   - Save

---

## 3. Create GitHub Project

1. Go to **Projects** tab → **New project** → **Board**
2. Name: `AHKFlowApp Backlog`
3. Create columns: `Todo`, `Ready`, `In Progress`, `Review`, `Done`

### Workflow (Manual)

GitHub Projects v2 has limited built-in automation. Manage workflow manually:

1. **Todo** — new issues created
2. **Ready** — reviewed and ready to start
3. **In Progress** — actively developing (when you open a PR)
4. **Review** — PR opened, awaiting code review
5. **Done** — PR merged and issue closed

---

## 4. Create Issues from Backlog

### Batch Script

See [`docs/scripts/create-github-issues.ps1`](../scripts/create-github-issues.ps1) — reads backlog files from `.claude/backlog/`, detects type/epic/interface labels, and creates GitHub Issues via `gh` CLI. Supports dry-run (default) and `-Execute` flag.

### Run

```powershell
gh auth status          # Verify authenticated
.\scripts\create-github-issues.ps1           # Dry run (default)
.\scripts\create-github-issues.ps1 -Execute  # Create issues for real
```

### Add Issues to Project

After creating issues, add them to your project:

```bash
# List issues and add to project
gh issue list --limit 100 --json number | ConvertFrom-Json | ForEach-Object { gh project item-add 1 --owner s205109 --url "https://github.com/s205109/AHKFlowApp/issues/$($_.number)" }
```

---

## Quick Checklist

- [ ] Create labels (epic labels, interface labels, workflow labels)
- [ ] Configure branch protection ruleset
- [ ] Create GitHub Project with columns
- [ ] Configure project workflow (manual)
- [ ] Run script to create issues from backlog
- [ ] Add issues to project
