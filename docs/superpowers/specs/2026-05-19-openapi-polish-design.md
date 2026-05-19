# OpenAPI / Swagger Polish Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Close the remaining OpenAPI documentation gaps. Most of the foundation is already in place — this is a small gap-filling exercise, not a greenfield setup.

## Current State (Verified)

- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:25-61` already wires:
  - `AddSwaggerGen` with a Bearer/JWT security definition and a global security requirement.
  - XML comment inclusion (`AHKFlowApp.API.xml` if present).
  - `ExampleFilters()` and `AddSwaggerExamplesFromAssemblies(...)`.
- `src/Backend/AHKFlowApp.API/AHKFlowApp.API.csproj:4` enables `<GenerateDocumentationFile>true</GenerateDocumentationFile>`.
- 7 of 10 controllers already carry `[ProducesResponseType]` annotations (63 occurrences across 9 files).
- Each authorised controller already declares its 401/403 response types.

## Gaps

1. **`WhoAmIController`** — has endpoints but no `[ProducesResponseType]` annotations (0 matches).
2. **`VersionController`** and **`HealthController`** — minimal annotations; verify their responses surface in the schema.
3. **`DevController`** — only 2 `[ProducesResponseType]` lines for the existing seed endpoint; new endpoints (hotkey seed, seed-all) added by the Seed Expansion spec must follow the same pattern.
4. **New controllers** added by other 2026-05-19 specs (`CategoriesController`, preview action on `DownloadsController`) must ship with full annotations from day one — this is a requirement carried into those specs, not a separate workstream.
5. **Bearer vs OAuth2 flow** — current scheme is bare Bearer/JWT. Swagger UI's "Authorize" button accepts a token but does not initiate an Entra/Azure AD auth-code flow. This is functional for developers who already have a token (e.g. from the Blazor app or a CLI) but is friction for first-time API users. **Decision: stay on Bearer for now**; document how to obtain a token in `docs/`. Defer the OAuth2 auth-code wiring until someone actually needs the Swagger Authorize button to run the flow end-to-end.
6. **`Application`-project DTOs**: their XML comments are not currently surfaced in Swagger because the Application project does not emit a doc file. Enabling it would surface DTO property descriptions in schemas. Low cost, decent payoff — enable.

## Scope

1. Add `[ProducesResponseType]` annotations to every action in:
   - `WhoAmIController` — success type + 401.
   - `VersionController` — success type.
   - `HealthController` — success type.
2. Coordinate with the Seed Expansion spec so new dev endpoints carry annotations.
3. Coordinate with the Categories spec so `CategoriesController` ships annotated.
4. Coordinate with the UX Bundle spec so the new preview endpoint and bulk-delete endpoints ship annotated.
5. Enable XML doc generation on `AHKFlowApp.Application.csproj`; extend `IncludeXmlComments` in `ApiExtensions.AddSwaggerDocs` to include `AHKFlowApp.Application.xml`.
6. Suppress `CS1591` (missing XML doc) only on `AHKFlowApp.Application` to avoid noise from already-undocumented internals; add `<summary>` comments to **DTOs and command/query records** only.

Out of scope: OAuth2 auth-code flow, `SwaggerResponseExample` example bodies, public-domain XML docs on internal types.

## Files In Scope

- `src/Backend/AHKFlowApp.API/Controllers/WhoAmIController.cs`
- `src/Backend/AHKFlowApp.API/Controllers/VersionController.cs`
- `src/Backend/AHKFlowApp.API/Controllers/HealthController.cs`
- `src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj` — enable doc generation, optionally suppress CS1591.
- `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:51-53` — extend `IncludeXmlComments` to also include `AHKFlowApp.Application.xml`.
- `src/Backend/AHKFlowApp.Application/DTOs/*.cs` — add `<summary>` XML comments on each DTO and its properties.
- `src/Backend/AHKFlowApp.Application/Commands/**/*.cs` and `Queries/**/*.cs` — `<summary>` on each record type.

## Test Strategy

- Smoke test: `GET /swagger/v1/swagger.json` returns 200 in Development (existing).
- Schema test using `Microsoft.OpenApi.Readers`:
  - Every operation declares at least one `2xx` response with a `$ref` to a schema (or a primitive).
  - DTO descriptions appear on at least one schema property (sanity check that the Application XML is wired in).

## Risks and Watchouts

- Adding XML comments on Application records produces many touched files. Stage as one PR for the doc generation wiring + one PR per project area for the comments to keep diffs reviewable.
- `CS1591` suppression must be scoped to the Application csproj only — don't hide warnings elsewhere.

## Done Criteria

- All three previously-bare controllers have `[ProducesResponseType]` on every action.
- DTO property descriptions appear in Swagger UI schemas.
- Schema validation test in CI green.
