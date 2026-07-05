# 003 - Scaffold initial solution structure

## Metadata

- **Epic**: Initial project / solution
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Create the initial project structure: Blazor WASM frontend, ASP.NET Core Web API backend, layered architecture, tests, and baseline infrastructure.

## User story

As a developer, I want a working solution skeleton so that feature development can start immediately with consistent patterns.

## Acceptance criteria

- [x] Solution contains projects for UI (Blazor WASM PWA), API (ASP.NET Core), Application/Core, Domain, Infrastructure. _(CLI deferred to 017 per AGENTS.md "Out of Scope".)_
- [x] Add repository .editorconfig for consistent code style.
- [x] Configure project references correctly.
- [x] MudBlazor is wired in with at least one example page.
- [x] Basic local run documentation exists.

## Out of scope

- Testing infra setup (see 004).
- Database setup (see 007).
- Docker setup (see 009).

## Notes / dependencies

- This item establishes naming, folder conventions, and DI boundaries early.

---

**Completed:** 2026-04-29
