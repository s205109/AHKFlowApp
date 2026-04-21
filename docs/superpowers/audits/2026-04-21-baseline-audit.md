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

_Populated in Task 5._

## Per-plan disposition

_Populated in Task 6._
