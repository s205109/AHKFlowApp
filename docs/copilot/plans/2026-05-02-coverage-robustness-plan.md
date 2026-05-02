# Coverage robustness plan

## Problem

The current CI gate enforces per-assembly line and branch thresholds from a merged Cobertura report via `scripts/check-coverage-thresholds.py`. That works, but recent PR failures showed the workflow is still brittle from a contributor perspective: the exact gate is easy to miss locally, some failures are caused by coverage-model details rather than meaningful behavior regressions, and the coverage documentation is partly out of sync with the live CI behavior.

## Current state observed

- CI runs `dotnet test --collect:"XPlat Code Coverage"` and merges results into `CoverageReport/Cobertura.xml`.
- `scripts/check-coverage-thresholds.py` enforces per-assembly thresholds for Domain, Application, Infrastructure, API, and UI.Blazor.
- `docs/development/coverage.md` documents local coverage usage and exclusions, but its gate description still mentions an older overall threshold model instead of the current per-assembly enforcement.
- The repo already has a good local reproduction path (`pwsh scripts/run-coverage.ps1` plus the Python threshold script), but it is not yet positioned as the default pre-push / pre-PR workflow.

## Selected direction

The chosen direction is **Option C — Hybrid guidance + smarter diagnostics**.

### Why this direction fits best

- It balances **workflow + CI + policy** without introducing heavy local enforcement.
- It focuses on reducing surprise failures by improving **prediction** and **explanation** before changing threshold strictness.
- It preserves the current per-assembly gate model while making it easier to understand, reproduce, and maintain.

### Constraints

- Optimize for a **balanced mix of developer workflow, CI diagnostics, and threshold policy**.
- Keep local enforcement **lightweight**: prefer docs and a canonical recommended command over mandatory local hooks.
- Prioritize **clearer CI failure diagnostics and exact local reproduction steps**.
- Keep CI guidance **light**, with concise next-action hints rather than speculative fix recommendations.

## Core objective

When a coverage gate fails, a contributor should not need to inspect raw Cobertura XML or download artifacts just to understand what happened and what to do next.

## Planned solution areas

### 1. Actionable CI diagnostics

Make the coverage gate output immediately understandable:

- show the failing assembly or assemblies
- show actual vs required line and branch metrics
- show the exact repo command(s) to reproduce locally
- add short next-step hints without trying to guess the full root cause

### 2. Canonical local verification path

Define one recommended pre-PR coverage workflow:

- center it on the existing repo tooling
- make it easy to copy/paste from docs or CI output
- keep it guidance-led rather than enforced by hooks

### 3. Coverage policy note

Document when to add tests versus when to exclude narrowly targeted code from coverage:

- exclusions should be intentional, narrow, and explainable
- helper or provider-specific coverage noise should be treated differently from untested business logic

### 4. Source-of-truth alignment

Reduce drift between:

- `.github/workflows/ci.yml`
- `scripts/check-coverage-thresholds.py`
- `docs/development/coverage.md`

Contributors should read the same rules that CI actually enforces.

## Expected contributor experience

If implemented well, future PR contributors should immediately understand:

1. which assembly failed
2. what the actual vs required metrics were
3. how to reproduce the failure locally
4. whether the next step is likely to be adding tests, reviewing exclusions, or checking coverage policy/docs

## Likely implementation candidates

- improve `scripts/check-coverage-thresholds.py` output formatting and messaging
- add or refine a repo-standard coverage verification wrapper/command in docs and/or scripts
- update `docs/development/coverage.md` to reflect the real per-assembly gate
- reduce duplicated threshold text between CI and docs where practical
- define a small written exclusion policy with examples

## Follow-up execution order

1. Improve coverage threshold failure output first.
2. Document the canonical local verification workflow.
3. Align docs and threshold/CI wording.
4. Add a brief exclusion-versus-tests policy.
