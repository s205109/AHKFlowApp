# Baseline Audit — 2026-04-21

> Snapshot captured during plan 1 of the codebase simplification roadmap.
> Every finding here is tagged with the plan that will handle it.

## PR #66 — unique-suffix Azure resource names

- Status: **merged** on 2026-04-21.
- Disposition: closed during plan 1.

## Outdated packages

Snapshot via `dotnet list package --outdated` on 2026-04-21.

```text
  Determining projects to restore...
  All projects are up-to-date for restore.

The following sources were used:
   https://api.nuget.org/v3/index.json
   C:\Program Files (x86)\Microsoft SDKs\NuGetPackages\

Project `AHKFlowApp.API` has the following updates to its packages
   [net10.0]: 
   Top-level Package                                                        Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore                               2.23.0      2.23.0     3.1.0 
   > Microsoft.AspNetCore.Authentication.JwtBearer                          10.0.6      10.0.6     10.0.7
   > Microsoft.EntityFrameworkCore.Design                                   10.0.6      10.0.6     10.0.7
   > Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore      10.0.6      10.0.6     10.0.7
   > Microsoft.Identity.Web                                                 4.7.0       4.7.0      4.8.0 
   > Serilog.Sinks.ApplicationInsights                                      5.0.0       5.0.0      5.0.1 

Project `AHKFlowApp.Application` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 
   > Microsoft.EntityFrameworkCore                 10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.Domain` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 

Project `AHKFlowApp.Infrastructure` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 
   > Microsoft.EntityFrameworkCore.SqlServer       10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.UI.Blazor` has the following updates to its packages
   [net10.0]: 
   Top-level Package                                            Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore                   2.23.0      2.23.0     3.1.0 
   > Microsoft.AspNetCore.Components.WebAssembly                10.0.6      10.0.6     10.0.7
   > Microsoft.AspNetCore.Components.WebAssembly.DevServer      10.0.6      10.0.6     10.0.7
   > Microsoft.Authentication.WebAssembly.Msal                  10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.API.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                                    Requested   Resolved   Latest
   > coverlet.collector                                 8.0.1       8.0.1      10.0.0
   > Microsoft.ApplicationInsights.AspNetCore           2.23.0      2.23.0     3.1.0 
   > Microsoft.AspNetCore.Authentication.JwtBearer      10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.Application.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > coverlet.collector                            8.0.1       8.0.1      10.0.0
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 

Project `AHKFlowApp.Domain.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > coverlet.collector                            8.0.1       8.0.1      10.0.0
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 
   > System.Security.Cryptography.Xml              10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.E2E.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                       Requested   Resolved   Latest
   > coverlet.collector                    8.0.1       8.0.1      10.0.0
   > Microsoft.AspNetCore.Mvc.Testing      10.0.6      10.0.6     10.0.7
   > Microsoft.Identity.Web                4.7.0       4.7.0      4.8.0 
   > System.Security.Cryptography.Xml      10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.Infrastructure.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > coverlet.collector                            8.0.1       8.0.1      10.0.0
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 

Project `AHKFlowApp.TestUtilities` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 
   > Microsoft.AspNetCore.Mvc.Testing              10.0.6      10.0.6     10.0.7
   > System.Security.Cryptography.Xml              10.0.6      10.0.6     10.0.7

Project `AHKFlowApp.UI.Blazor.Tests` has the following updates to its packages
   [net10.0]: 
   Top-level Package                               Requested   Resolved   Latest
   > coverlet.collector                            8.0.1       8.0.1      10.0.0
   > Microsoft.ApplicationInsights.AspNetCore      2.23.0      2.23.0     3.1.0 
   > System.Security.Cryptography.Xml              10.0.6      10.0.6     10.0.7
```

- Disposition: no upgrades in this roadmap cycle. Re-evaluated when individual plans need a specific package bumped. Tracked as a future backlog item.

## Security findings

Scan via `cck-security-scan` skill on 2026-04-21.

> Static analysis only — does not replace penetration testing, dynamic analysis, or threat modeling.

| ID | Severity | Layer | Summary | Disposition |
|----|----------|-------|---------|-------------|
| S-1 | low | secrets | `launchSettings.json` lines 10 and 43 — dev Docker SA password `AHKFlow_Dev!2026` committed in two launch profiles. Dev-only credential for local Docker SQL Server; not a production secret, but a real password in source control. | plan 3 |
| S-2 | low | secrets | `docs/environments.md:245` and `docs/superpowers/plans/2026-04-02-health-swagger-vscode.md:176,210` — same dev password appears in documentation example connection strings. | plan 6 |
| S-3 | medium | config | `src/Backend/AHKFlowApp.API/Extensions/ApiExtensions.cs:18-20` — CORS policy uses `AllowAnyMethod()` and `AllowAnyHeader()` alongside `AllowCredentials()`. Origins are correctly restricted via `WithOrigins(allowedOrigins)`, but method and header allowlists are broader than necessary. | plan 3 |

### Layer results

| Layer | Status | Findings |
|-------|--------|----------|
| 1. Package vulnerabilities | PASS | 0 CVEs across all 12 projects |
| 2. Secrets detection | WARN | Dev SA password in launchSettings.json and docs |
| 3. OWASP code patterns | PASS | No injection, XSS, insecure deserialization, or weak crypto |
| 4. Auth configuration | PASS | All controllers have explicit `[Authorize]` or `[AllowAnonymous]`; Azure AD via `AddMicrosoftIdentityWebApi` with secure defaults |
| 5. CORS configuration | WARN | `AllowAnyMethod()` + `AllowAnyHeader()` + `AllowCredentials()` — origins restricted, methods/headers not |
| 6. Data protection | PASS | Logs use identifiers only; no PII in log statements |

## Per-plan disposition

Each plan 2-6 opens by re-reading this section. Only items listed under its plan are in its scope.

### Plan 2 — Targeted coverage uplift
- No audit findings route here directly. Coverage gaps are discovered inside plan 2.

### Plan 3 — Code simplification
- S-1: Remove or rotate dev Docker SA password (`AHKFlow_Dev!2026`) from `launchSettings.json` (2 profiles). Replace with a random placeholder or env-var reference safe to commit.
- S-3: Tighten CORS policy — restrict `AllowAnyMethod()` and `AllowAnyHeader()` to explicit lists matching the frontend's actual needs.

### Plan 4 — Script + deploy.ps1 overhaul
- No security findings route here.
- Note: PR #66's unique-suffix variables are now written to `scripts/.env.<env>` after `deploy.ps1` runs — plan 4's preflight must read those values rather than hardcoding resource names.

### Plan 5 — Local-install path (no Azure)
- No audit findings route here directly. Scope is fixed by the roadmap spec.

### Plan 6 — Docs + consistency sweep
- S-2: Remove or replace dev password example strings in the two docs files flagged by the scan.
- Cross-reference: README, AGENTS.md, `.claude/CLAUDE.md`, `.github/**`.

### Deferred
- Package upgrades: 22 outdated entries (see Outdated packages section). Major bumps: `Microsoft.ApplicationInsights.AspNetCore` 2.23.0 → 3.1.0, `coverlet.collector` 8.0.1 → 10.0.0. Patch bumps: `Microsoft.*` 10.0.6 → 10.0.7, `Microsoft.Identity.Web` 4.7.0 → 4.8.0. Re-evaluate when individual plans need a specific bump.
- No Bicep/infra security findings to defer.
