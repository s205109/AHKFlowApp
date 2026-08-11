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

- Spec carrier: `backlog/078-ci-config-only-route.md`. Read that item before starting
  here.
- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §2 (P6) and
  §13 (private plans repo).
- Target: CI minutes on non-.NET changes drop to near zero for qualifying paths, against
  the wave-1 baseline in backlog 072.
