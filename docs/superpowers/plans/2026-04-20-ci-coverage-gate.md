# CI coverage gate — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add code-coverage collection, PR-visible reporting, and a minimum-line-coverage gate to `.github/workflows/ci.yml`, plus local reproduction.

**Architecture:** Single `build-test` job in `ci.yml` emits TRX + Cobertura via `dotnet test`; ReportGenerator merges per-project reports into one; outputs are surfaced in the PR (sticky comment + job summary + artifacts); a shell step parses ReportGenerator's JSON summary and fails the job when line coverage < 75%. Exclusions live in a checked-in `coverlet.runsettings` so local and CI numbers match.

**Tech Stack:** GitHub Actions, `dotnet test` + `coverlet.collector` (already referenced), `danielpalme/ReportGenerator-GitHub-Action@v5`, `EnricoMi/publish-unit-test-result-action@v2`, `marocchino/sticky-pull-request-comment@v2`.

**Reference spec:** `docs/superpowers/specs/2026-04-20-ci-coverage-gate-design.md`.

**Pre-work note:** CI workflow changes can only be fully verified by pushing and observing a PR run. Each workflow task ends with a commit; final verification is a single task at the end that pushes and inspects the PR.

---

## File structure

**Create:**
- `coverlet.runsettings` — repo root; exclusions for Program/Migrations/Tests, attribute-based exclusions.
- `scripts/run-coverage.ps1` — local reproduction producing the same numbers as CI.
- `docs/development/coverage.md` — short doc: how to run locally, how the gate works.

**Modify:**
- `.github/workflows/ci.yml` — expand `build-test` job: permissions, test args, merge/report, summary, comment, publish, artifacts, gate. `bicep-lint` job untouched.
- `.gitignore` — add `CoverageReport/` (TestResults already ignored).

**Out of scope:** changes to deploy workflows, new test projects, any src/** changes.

---

## Task 1: Add `coverlet.runsettings`

**Files:**
- Create: `coverlet.runsettings` (repo root)

- [ ] **Step 1: Create `coverlet.runsettings`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat code coverage">
        <Configuration>
          <Format>cobertura</Format>
          <ExcludeByAttribute>Obsolete,GeneratedCodeAttribute,CompilerGeneratedAttribute,ExcludeFromCodeCoverageAttribute</ExcludeByAttribute>
          <ExcludeByFile>**/Migrations/**/*.cs,**/Program.cs</ExcludeByFile>
          <Exclude>[*.Tests]*,[*.Tests.*]*</Exclude>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

- [ ] **Step 2: Verify it parses — run coverage locally**

```bash
dotnet test --configuration Release --collect:"XPlat Code Coverage" --results-directory TestResults --settings coverlet.runsettings
```

Expected: tests pass; one `coverage.cobertura.xml` per test project appears under `TestResults/<guid>/`.

- [ ] **Step 3: Confirm exclusions applied**

Open one generated `coverage.cobertura.xml`. Confirm:
- No `<class>` entry whose `filename` ends in `Program.cs`.
- No `<class>` entry whose `filename` contains `/Migrations/`.
- No `<class>` entries from `*.Tests` assemblies.

- [ ] **Step 4: Add `CoverageReport/` to `.gitignore`**

Append under the existing coverage block:

```
CoverageReport/
```

- [ ] **Step 5: Commit**

```bash
git add coverlet.runsettings .gitignore
git commit -m "chore: add coverlet.runsettings + ignore CoverageReport"
```

---

## Task 2: Update CI test step to produce TRX + Cobertura

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Replace the `dotnet test` line**

Current:

```yaml
      - run: dotnet test --configuration Release --no-build --verbosity normal
```

Replace with:

```yaml
      - name: Test with coverage
        run: >
          dotnet test --configuration Release --no-build --verbosity normal
          --logger "trx;LogFileName=test-results.trx"
          --collect:"XPlat Code Coverage"
          --results-directory TestResults
          --settings coverlet.runsettings
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: collect TRX + Cobertura in test step"
```

---

## Task 3: Widen job permissions + add ReportGenerator + job summary

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add job-level permissions to `build-test`**

Insert between `build-test:` and `runs-on: ubuntu-latest`:

```yaml
  build-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      checks: write
    steps:
```

Leave the workflow-level `permissions: { contents: read }` block in place — it applies to `bicep-lint`.

- [ ] **Step 2: Add ReportGenerator step after the test step**

Insert directly after the `Test with coverage` step:

```yaml
      - name: Merge coverage reports
        if: always()
        uses: danielpalme/ReportGenerator-GitHub-Action@5.3.0
        with:
          reports: 'TestResults/**/coverage.cobertura.xml'
          targetdir: 'CoverageReport'
          reporttypes: 'MarkdownSummaryGithub;JsonSummary;HtmlInline_AzurePipelines;Cobertura'
```

- [ ] **Step 3: Append the markdown summary to the job summary**

Insert directly after the ReportGenerator step:

```yaml
      - name: Append coverage summary to job summary
        if: always()
        run: cat CoverageReport/SummaryGithub.md >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: widen permissions + merge coverage into job summary"
```

---

## Task 4: Publish test results + sticky PR comment + upload artifacts

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add test-results publishing step**

Insert after the job-summary step:

```yaml
      - name: Publish test results
        if: always()
        uses: EnricoMi/publish-unit-test-result-action/linux@v2
        with:
          files: 'TestResults/**/*.trx'
```

- [ ] **Step 2: Add sticky PR comment step**

Insert after the publish-test-results step:

```yaml
      - name: Sticky coverage comment
        if: always() && github.event_name == 'pull_request'
        uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: coverage
          path: CoverageReport/SummaryGithub.md
```

- [ ] **Step 3: Add artifact upload**

Insert after the sticky-comment step:

```yaml
      - name: Upload coverage artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: |
            CoverageReport
            TestResults/**/*.trx
          retention-days: 14
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: publish test results, sticky coverage comment, upload artifacts"
```

---

## Task 5: Add coverage gate

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Insert gate step before the `dotnet format` step**

Place directly after the artifact upload and before `- run: dotnet format --verify-no-changes`:

```yaml
      - name: Enforce line coverage threshold
        if: always()
        env:
          THRESHOLD: '75'
        run: |
          set -euo pipefail
          LINE=$(jq -r '.summary.linecoverage' CoverageReport/Summary.json)
          echo "Line coverage: ${LINE}% (threshold: ${THRESHOLD}%)"
          awk -v l="$LINE" -v t="$THRESHOLD" 'BEGIN { exit (l+0 < t+0) }' \
            || { echo "::error::Line coverage ${LINE}% is below threshold ${THRESHOLD}%"; exit 1; }
```

Notes:
- `set -euo pipefail` so `jq` failure is fatal.
- `awk` comparison avoids `bc` (not guaranteed on runners) and pure-bash float arithmetic limitations.
- `if: always()` so the gate still runs when `dotnet test` fails the previous step — but test failure will already have failed the job by then; this just means the gate always prints its result.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: enforce line coverage >= 75% on merged report"
```

---

## Task 6: Enable NuGet caching on `setup-dotnet`

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Update the `setup-dotnet` step**

Replace:

```yaml
      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json
```

With:

```yaml
      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json
          cache: true
          cache-dependency-path: '**/*.csproj'
```

(No `packages.lock.json` files in this repo, so `**/*.csproj` is the correct hashing key.)

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: enable NuGet caching on setup-dotnet"
```

---

## Task 7: Local reproduction script

**Files:**
- Create: `scripts/run-coverage.ps1`

- [ ] **Step 1: Create `scripts/run-coverage.ps1`**

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
  Run tests with coverage locally and generate HTML + JSON summary matching CI.
.DESCRIPTION
  Requires: dotnet tool install -g dotnet-reportgenerator-globaltool
  Output:
    TestResults/**/coverage.cobertura.xml  (per-project Cobertura)
    coverage-report/index.html             (browsable HTML)
    coverage-report/Summary.json           (same shape CI gates on)
    coverage-report/SummaryGithub.md       (same markdown CI comments)
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (Test-Path TestResults)   { Remove-Item -Recurse -Force TestResults }
    if (Test-Path coverage-report) { Remove-Item -Recurse -Force coverage-report }

    dotnet test --configuration $Configuration `
        --collect:"XPlat Code Coverage" `
        --results-directory TestResults `
        --settings coverlet.runsettings
    if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

    reportgenerator `
        -reports:"TestResults/**/coverage.cobertura.xml" `
        -targetdir:"coverage-report" `
        -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary"
    if ($LASTEXITCODE -ne 0) { throw "reportgenerator failed" }

    $summary = Get-Content coverage-report/Summary.json | ConvertFrom-Json
    Write-Host ""
    Write-Host "Line coverage   : $($summary.summary.linecoverage)%" -ForegroundColor Cyan
    Write-Host "Branch coverage : $($summary.summary.branchcoverage)%" -ForegroundColor Cyan
    Write-Host "Report          : $(Resolve-Path coverage-report/index.html)" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
```

- [ ] **Step 2: Run it, verify outputs**

```bash
pwsh scripts/run-coverage.ps1
```

Expected: line and branch coverage printed; `coverage-report/index.html`, `coverage-report/Summary.json`, `coverage-report/SummaryGithub.md` all exist.

- [ ] **Step 3: Commit**

```bash
git add scripts/run-coverage.ps1
git commit -m "chore: add scripts/run-coverage.ps1 for local coverage"
```

---

## Task 8: Documentation

**Files:**
- Create: `docs/development/coverage.md`

- [ ] **Step 1: Create `docs/development/coverage.md`**

```markdown
# Code coverage

## Running locally

One-time setup:

\`\`\`bash
dotnet tool install -g dotnet-reportgenerator-globaltool
\`\`\`

Then from the repo root:

\`\`\`bash
pwsh scripts/run-coverage.ps1
\`\`\`

Outputs:

- `coverage-report/index.html` — browsable HTML report.
- `coverage-report/Summary.json` — the file the CI gate reads.
- `coverage-report/SummaryGithub.md` — the markdown posted as the PR sticky comment.

## Exclusions

Exclusions live in `coverlet.runsettings` (repo root) and apply to both local and CI runs:

- `**/Program.cs` — startup wiring.
- `**/Migrations/**/*.cs` — EF Core generated code.
- Assemblies matching `*.Tests` / `*.Tests.*`.
- Members with `[ExcludeFromCodeCoverage]`, `[GeneratedCode]`, `[CompilerGenerated]`, or `[Obsolete]`.

To exclude additional code, prefer `[ExcludeFromCodeCoverage]` on the class/method over widening the glob.

## CI gate

`.github/workflows/ci.yml` fails the PR if merged **line coverage** drops below **75%**. Branch coverage is reported but not gated.

The threshold is a literal in `ci.yml` (step `Enforce line coverage threshold`). Raising it is a normal PR like any other code change.

## Where to see coverage on a PR

1. Sticky comment on the PR titled `coverage` (updates in place on reruns).
2. The Actions run's job summary page (markdown table inline).
3. `coverage-report` artifact on the run — download for the full HTML report.

Fork PRs: the sticky comment and test-results check do not appear (GitHub does not grant write tokens to fork PRs). The gate still runs; the HTML artifact is still uploaded.
```

Replace `\`\`\`` with actual triple backticks when writing the file.

- [ ] **Step 2: Commit**

```bash
git add docs/development/coverage.md
git commit -m "docs: how to run coverage locally + how the CI gate works"
```

---

## Task 9: Push branch, open draft PR, verify end-to-end

This is the real verification — a workflow file only proves itself by running in Actions.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/027-ci-coverage-gate
```

- [ ] **Step 2: Open a draft PR**

```bash
gh pr create --draft --title "ci: add coverage gate (line >= 75%)" --body "$(cat <<'EOF'
## Summary

- Collect TRX + Cobertura from `dotnet test`.
- Merge per-project reports via ReportGenerator.
- Publish test results, sticky PR comment, job summary, HTML artifact.
- Enforce merged line coverage ≥ 75%.
- Local reproduction: `pwsh scripts/run-coverage.ps1`.

Spec: `docs/superpowers/specs/2026-04-20-ci-coverage-gate-design.md`.
Plan: `docs/superpowers/plans/2026-04-20-ci-coverage-gate.md`.

## Test plan

- [ ] CI run green on this PR.
- [ ] Sticky "coverage" comment appears with line + branch numbers.
- [ ] Job summary shows coverage markdown inline.
- [ ] `coverage-report` artifact uploads and contains `index.html`.
- [ ] Gate step logs the actual line-coverage number and passes.
- [ ] Temporarily bump THRESHOLD in workflow to 99, push, confirm gate fails; revert.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Watch the run**

```bash
gh pr checks --watch
```

Expected: `build-test` green; `bicep-lint` green.

- [ ] **Step 4: Verify PR artifacts**

On the PR page:
- A sticky comment with header `coverage` showing the coverage table.
- In the `build-test` run's summary: the same coverage table inline.
- A "Test Results" check with per-project test counts.
- An artifact `coverage-report` downloadable from the run.

Gate step log should contain: `Line coverage: <N>% (threshold: 75%)`.

- [ ] **Step 5: Failure-mode smoke test**

On a throwaway branch off this one, set `THRESHOLD: '99'` in `ci.yml`, push, confirm the job fails with `::error::Line coverage ...% is below threshold 99%`. Delete the branch. (Do not merge.)

- [ ] **Step 6: Mark PR ready, merge**

```bash
gh pr ready
```

After review + merge, delete the local branch:

```bash
git checkout main && git pull && git branch -d feature/027-ci-coverage-gate
```
