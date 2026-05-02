# Code coverage

## Canonical local verification

From the repo root, run:

```bash
pwsh .\scripts\run-coverage.ps1
```

That command is the recommended pre-push / pre-PR coverage check. It:

1. runs the test suite with `XPlat Code Coverage`
2. merges the per-project coverage files into `CoverageReport\Cobertura.xml`
3. appends the same threshold summary that CI adds to the job summary and PR comment
4. runs the same per-assembly threshold gate that CI enforces

If `CoverageReport` already exists and you only want to rerun the gate:

```bash
python .\scripts\check-coverage-thresholds.py
```

If you only want the local HTML report without enforcing thresholds:

```bash
pwsh .\scripts\run-coverage.ps1 -SkipThresholdCheck
```

## One-time setup

```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
git config core.hooksPath .githooks
```

The canonical gate also requires `python` on `PATH`.

That `core.hooksPath` setting enables the repo-managed `.githooks/pre-push` hook, which runs `pwsh .\scripts\run-coverage.ps1` automatically before each push.

The hook adds a few minutes per push. Skip it for WIP pushes with either:

```bash
SKIP_COVERAGE_HOOK=1 git push   # honored by the repo hook only
git push --no-verify            # bypasses every pre-push hook
```

Prefer `SKIP_COVERAGE_HOOK=1` so future pre-push hooks (lint, secret scan, etc.) still run.

## Outputs

- `CoverageReport/index.html` — browsable HTML report.
- `CoverageReport/Cobertura.xml` — merged Cobertura report that the threshold gate reads.
- `CoverageReport/Summary.json` — merged numeric summary from ReportGenerator.
- `CoverageReport/SummaryGithub.md` — markdown summary used in the PR sticky comment and Actions job summary.
- `TestResults/**/coverage.cobertura.xml` — per-project coverage files produced by `dotnet test`.

## CI gate

CI and the local verification path both use `scripts/check-coverage-thresholds.py` to enforce per-assembly line and branch thresholds from the merged Cobertura report.

The exact threshold values live in that script and are appended to the Actions job summary and PR sticky comment by the same script, so contributors read the same rules that CI enforces.

When the gate fails, start with `pwsh .\scripts\run-coverage.ps1`. The output calls out the failing assembly or assemblies, shows actual vs required line and branch metrics, and prints the exact local rerun commands.

## Where to see coverage on a PR

1. Sticky comment on the PR titled `coverage` (updates in place on reruns).
2. The Actions run's job summary page (markdown table inline).
3. `coverage-report` artifact on the run — download it for the full `CoverageReport` HTML and merged report files.

Fork PRs: the sticky comment and test-results check do not appear (GitHub does not grant write tokens to fork PRs). The gate still runs; the HTML artifact is still uploaded.

## Exclusions and policy

Exclusions live in `coverlet.runsettings` and apply to both local and CI runs:

- `**/Program.cs` — startup wiring.
- `**/Migrations/**/*.cs` — EF Core generated code.
- Assemblies matching `*.Tests` / `*.Tests.*`.
- Members with `[ExcludeFromCodeCoverage]`, `[GeneratedCode]`, `[CompilerGenerated]`, or `[Obsolete]`.

Prefer the narrowest explainable exclusion that solves the specific coverage noise. In practice:

| Situation | Preferred action |
|---|---|
| Domain logic, application handlers, validators, controller behavior, or other business flow is uncovered | Add or update tests. |
| Generated code, startup wiring, migrations, or compiler-generated members are uncovered | Exclude narrowly in `coverlet.runsettings` or with `[ExcludeFromCodeCoverage]`. |
| A small helper or provider-specific member creates noisy coverage with little behavioral value | Prefer a targeted attribute on the member or type over widening file globs. |
| An entire feature, folder, or assembly is tempting to exclude | Do not broaden exclusions. Treat that as a sign to add tests or revisit the design. |

For new exclusions, prefer `[ExcludeFromCodeCoverage]` on the specific class or method over widening a glob in `coverlet.runsettings`.
