# OpenAPI / Swagger Polish Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Make the OpenAPI document discoverable and accurate:

- Every controller action declares its response shape via `[ProducesResponseType]`.
- Error responses are uniformly `ProblemDetails` (RFC 9457).
- Azure AD security scheme is registered so Swagger UI gets an Authorize button.
- XML doc comments surface as endpoint descriptions.

## Current State

- 8 controllers (Hotstrings, Hotkeys, Profiles, Preferences, Dev, Downloads, Dashboard, Health/Version/WhoAmI).
- `GlobalExceptionMiddleware` returns RFC 9457 `ProblemDetails` on unhandled errors — but action signatures don't advertise it.
- No `[ProducesResponseType]` annotations anywhere.
- No security scheme registered, despite every endpoint requiring `[Authorize]` + `[RequiredScope("access_as_user")]`.
- XML doc generation not enabled on the API/Application/Domain csproj files.

## Scope

1. `[ProducesResponseType(typeof(T), StatusCodes.Status2xxOK)]` on every action — happy path plus `400`, `401`, `403`, `404`, `409` as appropriate. All non-2xx use `typeof(ProblemDetails)`.
2. Controller-level `[Produces("application/json")]` and (for write actions) `[Consumes("application/json")]`.
3. Register OAuth2 (Authorization Code with PKCE) security scheme in `AddSwaggerGen` pointing at the existing Entra ID tenant, scope `access_as_user`. Add `OperationFilter` (or global `SecurityRequirement`) so each action lists the scheme.
4. Configure `UseSwaggerUI` with the OAuth client id so the "Authorize" button works end-to-end.
5. Enable XML doc comments:
   - `<GenerateDocumentationFile>true</GenerateDocumentationFile>` on `AHKFlowApp.API.csproj` (and any others whose types appear in the schema, e.g. `AHKFlowApp.Application` for DTOs).
   - `IncludeXmlComments` call in Swagger setup pointing at every emitted XML file.
   - Suppress `CS1591` globally OR add `<summary>` to every public type — pick the second for the API project only.

Out of scope: full `SwaggerResponseExample` examples. Deferred.

## Files In Scope

- `src/Backend/AHKFlowApp.API/Program.cs` (or a new `src/Backend/AHKFlowApp.API/Extensions/SwaggerSetup.cs`) — security scheme, XML includes, OAuth client config.
- Every controller in `src/Backend/AHKFlowApp.API/Controllers/`:
  - `HotstringsController.cs`
  - `HotkeysController.cs`
  - `ProfilesController.cs`
  - `PreferencesController.cs`
  - `CategoriesController.cs` (post Categories spec)
  - `DevController.cs`
  - `DownloadsController.cs`
  - `DashboardController.cs`
  - `HealthController.cs`, `VersionController.cs`, `WhoAmIController.cs`
- `Directory.Build.props` — enable XML doc generation across backend projects whose types appear in schemas.

## Test Strategy

- Smoke test: `GET /swagger/v1/swagger.json` returns 200 in Development.
- Schema test using `Microsoft.OpenApi.Readers`:
  - Document parses without errors.
  - At least one security scheme is declared.
  - Every operation declares at least one `2xx` response with a `$ref` to a schema (or a primitive).
- Manual: open Swagger UI, click Authorize, complete the Entra flow, fire a request — gets 200.

## Risks and Watchouts

- `[ProducesResponseType]` types must match what controllers actually return after `result.ToActionResult(this)` — verify by reading the `Result<T>` → HTTP mapping for each path.
- XML comment generation may surface `CS1591` warnings for every undocumented public member — scope the build setting to the API project to limit noise, then fix descriptions iteratively.
- OAuth flow config requires the Entra app registration to allow the Swagger redirect URI for `/swagger/oauth2-redirect.html`; coordinate with whichever environment Swagger is exposed in (likely only Development).

## Done Criteria

- Swagger UI shows accurate request/response schemas and an Authorize button that completes the Entra flow.
- Every action has at least `[ProducesResponseType]` for its success status plus all relevant error statuses.
- XML doc summaries appear as endpoint descriptions in Swagger UI.
- Schema validation test in CI green.
