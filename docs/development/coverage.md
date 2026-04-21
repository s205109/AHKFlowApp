# Code coverage

## Running locally

One-time setup:

```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
```

Then from the repo root:

```bash
pwsh scripts/run-coverage.ps1
```

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

`.github/workflows/ci.yml` enforces two thresholds on the merged report:

| Metric | Threshold |
|---|---|
| Line coverage | ≥ 70% |
| Branch coverage | ≥ 40% |

Both gates must pass. Thresholds are literals in `ci.yml` — raising one is a normal PR change.

## Where to see coverage on a PR

1. Sticky comment on the PR titled `coverage` (updates in place on reruns).
2. The Actions run's job summary page (markdown table inline).
3. `coverage-report` artifact on the run — download for the full HTML report.

Fork PRs: the sticky comment and test-results check do not appear (GitHub does not grant write tokens to fork PRs). The gate still runs; the HTML artifact is still uploaded.
