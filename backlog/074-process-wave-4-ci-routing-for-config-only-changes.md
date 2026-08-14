# 074 - Process wave 4 - CI routing for config-only changes

## Metadata

- **Epic**: Development process
- **Type**: Process / CI
- **Interfaces**: none (CI workflows, local gate)
- **Difficulty**: complex
- **Stage**: 1-pickup
- **Depends on**: 078-ci-config-only-route

## Summary

Wave 4 of the development process. A pull request that changes only configuration files
runs the whole .NET build and test suite today. This wave routes such a pull request to a
short gate instead.

## User story

As a contributor, I want a configuration-only pull request to run only the checks that
apply to it so that I do not wait for a full .NET build to approve a one-line change.

## Acceptance criteria

- [ ] Backlog 078 carries the design for this wave: its spec defines the path allowlist,
      the validator list, and the drift check. This item ships that design.
- [ ] Both the local gate and CI route a configuration-only change to the short gate.
- [ ] The route is proven by a fixture-driven routing test.
- [ ] A drift check fails when `ci.yml` and the local gate disagree about the allowlist.

## Out of scope

- Writing the spec. Backlog 078 is the spec carrier for this wave.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-14-ci-config-only-route-design.md` (private plans
  repo). Read it before starting here — it is the design this item ships.
- Spec carrier: `backlog/done/078-ci-config-only-route.md`, closed 2026-08-14.
- Parent spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md`
  §2 (P6) and §13.
- The spec leaves three questions for the plan: which workflow linter and how it is
  pinned, the `config-validators` runner OS, and whether `Reason` names every deciding
  file.
- Target: CI minutes on non-.NET changes drop to near zero for qualifying paths. That is a
  direction, not a percentage: backlog 072 has no established baseline yet.
