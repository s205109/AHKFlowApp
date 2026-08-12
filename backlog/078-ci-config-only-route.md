# 078 - CI config-only route

## Metadata

- **Epic**: Development process
- **Type**: CI
- **Interfaces**: none (CI workflows, local gate)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

A pull request that changes only configuration files runs the full .NET build and test
suite. This item designs the short route for those pull requests: which paths qualify,
which validators run instead, and how the local gate and CI stay in agreement. It is the
spec carrier for wave 4 (backlog 074).

## User story

As a contributor, I want a configuration-only pull request to run configuration checks
only so that CI minutes are spent on code that changed.

## Acceptance criteria

- [ ] A spec exists for this item and is approved.
- [ ] The spec carries the path allowlist: `.pr_agent.toml`, `.github/workflows/**`,
      `.githooks/**`, `scripts/**/*.ps1`.
- [ ] The spec states the disqualifying file kinds. Any changed file that is compiled
      source or a build input keeps the full gate: `*.cs`, `*.razor`, `*.csproj`,
      `*.props` (`Directory.*.props` included), `*.targets`, `*.sln`, `global.json`.
- [ ] Kind decides, never location. A `.csproj` under `docs/` still disqualifies a run,
      and a `.md` file under `src/` still counts as documentation.
- [ ] The spec carries the validator list: what runs on the short route for each qualifying
      file kind.
- [ ] The spec defines a fixture-driven routing test and a `ci.yml` drift check.

## Out of scope

- Implementation. Backlog 074 ships this design.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P6)
  (private plans repo). Write a dedicated spec for this item before planning it.
- Dependency of backlog 074 (wave 4).
- `ci.yml` already treats every `**/*.md` path as documentation wherever it sits. The new
  route must not contradict that rule.
