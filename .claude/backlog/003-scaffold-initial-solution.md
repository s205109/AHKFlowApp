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

- [ ] Solution contains projects for UI (Blazor WASM PWA), API (ASP.NET Core), Application/Core, Domain, Infrastructure, and CLI.
- [ ] Add repository .editorconfig for consistent code style.
- [ ] Add Copilot instructions in the .github/ folder (instructions, prompts, agent personas).
- [ ] Configure project references correctly.
- [ ] MudBlazor is wired in with at least one example page.
- [ ] Basic local run documentation exists.

## Out of scope

- Testing infra setup (see 004).
- Database setup (see 007).
- Docker setup (see 009).

## Notes / dependencies

- This item establishes naming, folder conventions, and DI boundaries early.
