# 078 - CI config-only route

## Metadata

- **Epic**: Development process
- **Type**: CI
- **Interfaces**: none (CI workflows, local gate)
- **Difficulty**: complex
- **Stage**: 9-ship

## Summary

A pull request that changes only configuration files runs the full .NET build and test
suite. This item designs the short route for those pull requests: which paths qualify,
which validators run instead, and how the local gate and CI stay in agreement. It is the
spec carrier for wave 4 (backlog 074).

## User story

As a contributor, I want a configuration-only pull request to run configuration checks
only so that CI minutes are spent on code that changed.

## Acceptance criteria

- [x] A spec exists for this item and is approved.
- [x] The spec carries the path allowlist: `.pr_agent.toml`, `.github/workflows/**`,
      `.githooks/**`, `scripts/**/*.ps1`. §4.4 covers all four. It states them as file
      kinds plus directory scopes rather than glob paths, because `scripts/**/*.ps1`
      missed the 23 PowerShell suites in `tests/` and the 5 hooks in `.claude/hooks/`.
- [x] The spec states the disqualifying file kinds. Any changed file that is compiled
      source or a build input keeps the full gate: `*.cs`, `*.razor`, `*.csproj`,
      `*.props` (`Directory.*.props` included), `*.targets`, `*.sln`, `global.json`.
      §4.5 adds `*.slnx`, `*.runsettings`, and `.editorconfig`.
- [x] Kind decides, never location. A `.csproj` under `docs/` still disqualifies a run,
      and a `.md` file under `src/` still counts as documentation. §4.6, and §7.2 tests
      one such case per directory scope.
- [x] The spec carries the validator list: what runs on the short route for each qualifying
      file kind. §6, with §6.1 putting CI and the pre-push hook behind one runner.
- [x] The spec defines a fixture-driven routing test and a `ci.yml` drift check. §7.1 and
      §7.3.

## Out of scope

- Implementation. Backlog 074 ships this design.

## Notes / dependencies

- Spec written: `docs/superpowers/specs/2026-08-14-ci-config-only-route-design.md`
  (private plans repo). Parent spec:
  `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P6).
- Dependency of backlog 074 (wave 4). 074 ships the implementation.
- `ci.yml` already treats every `**/*.md` path as documentation wherever it sits. The new
  route must not contradict that rule. §4.2 of the spec absorbs the rule instead of
  running beside it, and §4.4 keeps the non-Markdown assets under `docs/` on the short
  route as they are today.
- Three questions stay open for the plan: which workflow linter and how it is pinned, the
  `config-validators` runner OS, and whether `Reason` names every deciding file.
