# 010 - Create CI/CD pipeline

## Metadata

- **Epic**: CI/CD
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Create a basic CI/CD pipeline that builds and tests the solution, then deploys the UI and API.

## User story

As a developer, I want automated build/test/deploy so that changes reach a staging/production environment reliably.

## Acceptance criteria

- [x] CI runs on pull requests: build + unit tests.
- [x] CD runs on main: build + tests + publish artifacts.
- [x] UI deploys to Azure Static Web Apps (or equivalent).
- [x] API deploys via container (or equivalent) to Azure or another agreed target.

## Out of scope

- Blue/green deployments.

## Notes / dependencies

- Requires the scaffold in 003.

---

**Completed:** 2026-04-29
