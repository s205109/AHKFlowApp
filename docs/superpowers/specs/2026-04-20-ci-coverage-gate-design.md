# CI coverage gate (design)

## Context

`.github/workflows/ci.yml` runs restore, build, test, and `dotnet format --verify-no-changes` on `pull_request` to `main`. It does not collect TRX, does not collect Coverlet output, does not publish test or coverage summaries, and does not enforce a coverage threshold.

Relevant existing state:

- Test projects already reference `coverlet.collector`, so `dotnet test --collect:"XPlat Code Coverage"` works without new packages.
- `coverage-report/` exists locally and is gitignored (`.gitignore` excludes `coverage-report/`, `coverage*.xml`, `coverage*.json`, `*.trx`), indicating an ad-hoc local flow today.
- A local snapshot shows roughly **79% line / 58% branch** coverage — an initial gate must not break CI on day one.

Reference: [Sean Killeen, "Beautiful .NET Test Reports Using GitHub Actions" (2024)](https://seankilleen.com/2024/03/beautiful-net-test-reports-using-github-actions/).

## Goal

Make coverage a first-class signal on every PR:

1. Collect TRX + Cobertura in CI.
2. Publish test results and a coverage summary inside the PR (reviewer-visible, not buried in logs).
3. Enforce a minimum **line coverage** threshold on the merged report.
4. Keep local reproduction one command, producing the same numbers CI sees.

Non-goals: external coverage services (Codecov/Coveralls), branch-coverage enforcement (visible only this iteration), changes to the `bicep-lint` job.

## Options considered

### Option 1 — GitHub-native PR UX with marketplace actions *(chosen)*

Extend `ci.yml` to emit TRX + Cobertura; merge with `danielpalme/ReportGenerator-GitHub-Action`; publish unit test results with `EnricoMi/publish-unit-test-result-action`; post a sticky PR comment via `marocchino/sticky-pull-request-comment`; also write coverage markdown to the job summary; enforce threshold by parsing ReportGenerator's JSON summary.

Pros: matches the reference article; keeps everything inside GitHub Actions; produces both human-friendly output and a machine-enforced gate.
Cons: requires widening workflow permissions (`pull-requests: write`, `checks: write`); third-party action supply chain.

### Option 2 — Enforcement + artifacts, no PR comment

Collect coverage, fail below threshold, upload HTML/XML artifacts. No PR comment.

Pros: minimal permission footprint; no third-party actions with write scope.
Cons: reviewers must open an artifact or action log — weaker signal.

### Option 3 — External coverage service

Push to Codecov/Coveralls.

Pros: rich annotations, historical trend.
Cons: adds an external dependency, extra secret governance, drift from the reference article. Not aligned with the request.

**Decision: Option 1.**

## Approach

### Workflow changes (`.github/workflows/ci.yml`)

Modify the existing `build-test` job (don't add a new job — coverage is part of the PR gate, not a parallel signal):

1. Upgrade job-level permissions (not workflow-level — contain blast radius):
   ```yaml
   permissions:
     contents: read
     pull-requests: write   # sticky coverage comment
     checks: write          # publish-unit-test-result
   ```
2. Enable NuGet caching on `actions/setup-dotnet` (`cache: true`, `cache-dependency-path: '**/packages.lock.json'` if lock files exist, otherwise `**/*.csproj`). Unrelated but cheap, and this is the workflow touched.
3. Change the test step:
   ```yaml
   - run: >
       dotnet test --configuration Release --no-build
       --logger "trx;LogFileName=test-results.trx"
       --collect:"XPlat Code Coverage"
       --results-directory TestResults
       --settings coverlet.runsettings
   ```
4. After tests (all with `if: always()` so they run on test failure too):
   - **Merge + report** with `danielpalme/ReportGenerator-GitHub-Action@v5`:
     - Input: `TestResults/**/coverage.cobertura.xml`
     - Reports: `MarkdownSummaryGithub;JsonSummary;HtmlInline_AzurePipelines;Cobertura`
     - Output dir: `CoverageReport`
   - **Append Markdown summary** to `$GITHUB_STEP_SUMMARY`:
     ```bash
     cat CoverageReport/SummaryGithub.md >> "$GITHUB_STEP_SUMMARY"
     ```
   - **Publish unit test results** via `EnricoMi/publish-unit-test-result-action/linux@v2` against `TestResults/**/*.trx`.
   - **Sticky PR comment** via `marocchino/sticky-pull-request-comment@v2` with the markdown file as body and `header: coverage` so repeat runs update in place.
   - **Upload artifacts**: `CoverageReport/` (HTML + Cobertura + JSON) and `TestResults/**/*.trx`.
5. **Gate step** (last, before `dotnet format` — a failing format check shouldn't mask a failing gate, and vice versa):
   ```bash
   LINE=$(jq -r '.summary.linecoverage' CoverageReport/Summary.json)
   THRESHOLD=75
   awk -v l="$LINE" -v t="$THRESHOLD" 'BEGIN { exit (l+0 < t+0) }' \
     || { echo "::error::Line coverage $LINE% < threshold $THRESHOLD%"; exit 1; }
   ```
   Uses `awk` because `bc` isn't guaranteed on the runner and pure-bash float comparison is awkward.

### `coverlet.runsettings` (new, repo root)

Single source of truth for exclusions — runs identically local and CI.

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

Excluded categories and why:

- **Test assemblies** — don't count tests-of-tests.
- **EF Core migrations** — generated; noise.
- **`Program.cs`** — top-level startup wiring, exercised by integration tests but not meaningfully branch-tested.
- **`[ExcludeFromCodeCoverage]`** respected — escape hatch for DI extension methods, record-style DTOs with custom code, etc.

Startup extension methods (e.g., `ApiExtensions`, `DevEnvironment`) stay **in** the measurement — they are real production code paths and exercised by integration tests.

### Local reproduction

Add `scripts/run-coverage.ps1` producing the same output shape CI produces:

```powershell
dotnet test --configuration Release `
  --collect:"XPlat Code Coverage" `
  --results-directory TestResults `
  --settings coverlet.runsettings
reportgenerator `
  -reports:"TestResults/**/coverage.cobertura.xml" `
  -targetdir:"coverage-report" `
  -reporttypes:"Html;MarkdownSummaryGithub;JsonSummary"
```

Documented in `docs/development/coverage.md` (new, short — command + interpretation of Summary.json + how the CI gate decides pass/fail).

Requires `dotnet tool install -g dotnet-reportgenerator-globaltool` on the dev machine — documented but not auto-installed.

## Security / permissions considerations

- Job-level permissions, not workflow-level. `bicep-lint` stays on default `contents: read`.
- **Fork PRs**: `pull_request` from forks gets a read-only `GITHUB_TOKEN`. The sticky comment and check-publishing will silently no-op — coverage still collects and the gate still runs, but reviewers of fork PRs see only artifacts and the job summary. Not worth switching to `pull_request_target` (security footgun) for a repo that doesn't currently take external contributions.
- Third-party actions are pinned to major version tags (`@v2`, `@v5`), matching current workflow convention. SHA-pinning is a broader project decision; not introduced here.

## Threshold policy

- **Initial gate: line coverage ≥ 75%** on the merged report. Headroom vs. current ≈79%, so day-one green.
- **Branch coverage (currently ≈58%)** displayed in the PR comment and job summary, **not** gated. Gate can be added later once branch coverage is raised deliberately.
- Threshold is a literal in the workflow file (not a repo variable) so the value lives with the code that enforces it and moves through PR review like any other change.

## Risks

- **Threshold oscillation.** A PR that removes well-covered code could drop coverage below 75% even though it adds no untested code. Accepted risk; Option 1 makes the signal obvious so the author can add tests or bring the threshold down in the same PR.
- **Action breaking changes.** Floating on major tags means a new major from any of the three actions breaks CI until pinned. Acceptable given current convention; revisit if it happens.
- **Runner time.** Coverage + ReportGenerator adds ≈30–60s per CI run. Not a concern at current PR volume.
- **Windows-specific paths.** Tests currently run on `ubuntu-latest`. `coverlet.runsettings` paths use forward slashes and `**/` globs; works on both OSes if the workflow is ever matrix-extended.

## Acceptance

- `ci.yml` fails a PR when merged line coverage < 75%.
- A sticky comment titled "Coverage" appears on every PR, updating in place across reruns.
- The Actions job summary shows the coverage table inline.
- `scripts/run-coverage.ps1` reproduces the same `Summary.json` numbers locally.
- `docs/development/coverage.md` explains both.
- `dotnet format --verify-no-changes` still runs and still fails independently of the coverage gate.

## Unresolved questions

- runsettings: exclude `ApiExtensions.cs` / other DI wiring files too, or leave in?
- script: PowerShell-only ok, or also a bash version for WSL/devcontainer users?
- comment header: `coverage` vs something more specific (e.g., `coverage-pr`)?
