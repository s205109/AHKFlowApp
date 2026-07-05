# AHKFlow - Product Vision & .NET Architecture Overview

## 1. Purpose

This document defines the product vision, functional scope, and high-level .NET architecture for AHKFlow.

It is the main product and architecture context document for the repository. Use it when you need to understand what AHKFlow is, how the .NET solution is structured, and which product capabilities are current or intentionally out of scope.

For a shorter design-only summary, see [Claude Design Brief](claude-design-brief.md).

## 2. Product Overview

AHKFlow is an **AutoHotkey Hotstring Manager & CLI**: a .NET application for managing AutoHotkey hotstrings and hotkeys on Windows. It helps users define reusable automation snippets, organize them into profiles and categories, generate valid `.ahk` scripts, and download those scripts from a web UI or CLI.

The web UI and the `ahkflow` CLI are both first-class, shipped interfaces in the first version. Neither is an add-on: the CLI is core to the product for scripted and power-user workflows.

The product-facing name is AHKFlow. The repository and .NET solution are named `AHKFlowApp`.

## 3. Product Vision

Make creation, management, and distribution of AutoHotkey automation simple, structured, and maintainable.

AHKFlow should feel like a focused productivity tool: practical, predictable, easy to scan, and strong enough for users who maintain many automations across different contexts.

## 4. Product Principles

- Keep automation definitions centralized and easy to reason about.
- Make hotstrings, hotkeys, profiles, and categories quick to search, filter, compare, and edit.
- Treat generated scripts as transparent outputs of user-managed data.
- Support both interactive users through the web UI and power users through the CLI.
- Keep the architecture testable and friendly to AI-assisted development without turning product documents into implementation manuals.

## 5. Current Scope

- Hotstring management via web UI and CLI.
- Hotkey management via web UI.
- Profile creation and management.
- Category tagging and filtering for hotstrings and hotkeys.
- Header and footer templates for generated `.ahk` profile scripts.
- Script preview and generation per profile.
- Script download via web UI, Web API, and CLI.
- Zip download of generated scripts.
- Entity version history with revert for hotstrings, hotkeys, profiles, and categories.
- Recycle bin for soft-deleted entities (restore or permanent purge).
- In-app changelog.
- Entra ID authentication for normal UI/API/CLI use.
- Local no-Azure development mode for trusted development and homelab scenarios.

## 6. Future / Out of Scope

- CLI commands for managing hotkeys (the shipped CLI already covers hotstrings, downloads, and auth — only hotkey commands are pending).
- Hotkey blacklisting, such as reserved Windows hotkeys.
- Custom AHK script management beyond generated profile scripts.
- Runtime execution of AutoHotkey scripts.

## 7. Domain Model

- **Hotstring** - A text replacement trigger, such as `btw` expanding to `by the way`.
- **Hotkey** - A keyboard shortcut that triggers an action.
- **Profile** - A named grouping of hotstrings and hotkeys used to generate one `.ahk` script.
- **Category** - A user-defined tag for organizing and filtering hotstrings and hotkeys.
- **Script** - A generated `.ahk` file derived from a profile and its assigned definitions.
- **Trigger** - The abbreviation or key combination that activates a hotstring or hotkey.
- **Replacement** - The expanded text used by a hotstring.

## 8. Primary Interfaces

### 8.1 Web UI

The web UI is the primary interactive experience. It is a Blazor WebAssembly PWA built with MudBlazor.

Current UI areas:

- Dashboard
- Hotstrings
- Hotkeys
- Downloads
- Profiles
- Categories
- Settings and health/supporting views

### 8.2 Web API

The ASP.NET Core Web API is the source of truth for authorization, validation, persistence, and script generation.

Current API capability areas:

- Hotstring endpoints
- Hotkey endpoints
- Profile endpoints
- Category endpoints
- Dashboard and preference endpoints
- Script preview and download endpoints
- Health, version, and identity endpoints

### 8.3 CLI

The CLI is a .NET console app for power users and automation workflows. It consumes the Web API rather than maintaining its own data store.

Current CLI areas:

- `ahkflow login`
- `ahkflow logout`
- `ahkflow hotstring new`
- `ahkflow hotstring list`
- `ahkflow download ahk`
- `ahkflow download zip`

## 9. .NET Solution Architecture

```text
Blazor WebAssembly PWA
        |
        | HTTPS
        v
ASP.NET Core Web API <--------- .NET CLI
        |
        v
Application Layer
  - Explicit use cases (IUseCase/IUseCaseHandler) — commands and queries
  - FluentValidation
  - Ardalis.Result outcomes
  - DTOs and explicit mappings
  - Script generation logic
        |
        v
Infrastructure Layer
  - EF Core
  - SQL Server provider
  - Migrations
        |
        v
SQL Server
```

### 9.1 Project Shape

- `src/Backend/AHKFlowApp.Domain` contains domain entities and value concepts.
- `src/Backend/AHKFlowApp.Application` contains DTOs, commands and queries with explicit use case handlers, validation, mappings, and application services.
- `src/Backend/AHKFlowApp.Infrastructure` contains EF Core persistence and migrations.
- `src/Backend/AHKFlowApp.API` contains controllers, middleware, API composition, OpenAPI, authentication, and hosting.
- `src/Frontend/AHKFlowApp.UI.Blazor` contains the Blazor WebAssembly PWA.
- `src/Tools/AHKFlowApp.CLI` contains the command-line client.

### 9.2 Request Flow

```text
HTTP request
  -> Controller
  -> IUseCase<TRequest,TResult>.ExecuteAsync(command/query)
  -> ValidatingUseCase<TRequest,TResult> (FluentValidation)
  -> IUseCaseHandler<TRequest,TResult>
  -> EF Core persistence
  -> Result mapped to HTTP response
```

The UI and CLI use typed API clients. They should stay aligned with the API behavior, but the UI is not coupled to the Application project as a shared contract assembly.

## 10. Technology Stack

- .NET 10 across the solution.
- Blazor WebAssembly PWA with MudBlazor for the frontend.
- ASP.NET Core Web API with controller-based endpoints.
- Explicit use cases (IUseCase/IUseCaseHandler) for commands and queries.
- Ardalis.Result for handler outcomes.
- FluentValidation through the ValidatingUseCase<TRequest,TResult> decorator.
- EF Core with SQL Server for persistence.
- System.CommandLine for the CLI.
- MSAL and Microsoft Identity Web for authentication flows.
- Serilog and optional Application Insights for diagnostics.
- MinVer for semantic versioning from git tags.

## 11. Security & Identity

- Entra ID is the normal identity provider.
- The Blazor UI uses MSAL browser authentication.
- The CLI uses MSAL.NET device-code authentication.
- The API validates bearer tokens and enforces authorization/data ownership.
- Local no-Azure mode uses a fixed synthetic identity and is limited to trusted development scenarios.

## 12. Quality & Testing

The solution is designed to be testable across layers:

- Domain tests for entity behavior.
- Application tests for validators, handlers, and script generation.
- API integration tests for serialization, middleware, authorization, and endpoint behavior.
- Infrastructure tests using real SQL Server behavior.
- bUnit tests for Blazor components.
- CLI tests for command parsing, output, and API-client behavior.
- End-to-end tests for browser workflows.

## 13. Local Development & Deployment

Local development supports:

- Repository-root `dotnet run` launcher for API plus UI.
- LocalDB and Docker SQL Server workflows.
- Docker Compose for SQL Server, API, and Blazor UI with local no-Azure auth.

Azure deployment uses:

- Static Web Apps for the frontend.
- .NET App Service package deployment for the API.
- Azure SQL Database for persistence.
- GitHub Actions for build, test, migration, and deployment workflows.

## 14. Related Documents

- [Claude Design Brief](claude-design-brief.md)
- [Authentication Architecture](authentication.md)
- [Search Semantics](search-semantics.md)
- [Configuration Strategy](../development/configuration-strategy.md)
- [Deployment Getting Started](../deployment/getting-started.md)
