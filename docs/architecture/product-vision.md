# AHKFlowApp – Product Vision & Architecture Overview

## 1. Introduction

### 1.1 Purpose of this Document

This document defines the **product vision**, **functional scope**, and **high-level architectural intent** of AHKFlowApp.

It provides a shared understanding of:

- What the product is
- Why it exists
- How it is conceptually structured

This document is intentionally **non-prescriptive** and evolves with the product.

### 1.2 Product Overview

AHKFlowApp is a .NET application for managing AutoHotkey hotstrings and hotkeys on Windows. It enables users to:

- Centrally define hotstrings
- Organize hotstrings and hotkeys by profile
- Generate valid `.ahk` scripts per profile
- Access, manage, and download generated scripts via a Web UI and a CLI

---

## 2. Vision & Principles

### 2.1 Product Vision

Make creation, management, and distribution of AutoHotkey automation simple, structured, and maintainable.

### 2.2 Design Principles

The application is designed to be:

- Maintainable over time
- Clearly structured and testable by default
- Friendly to AI-assisted development
- Extensible without breaking changes

---

## 3. Scope Definition

### 3.1 In Scope (Current)

- Hotstring management via UI and CLI
- Hotkey management via UI
- Profile creation and management
- Define header templates for generated .ahk files
- Generation of AutoHotkey `.ahk` files per profile
- Script download via Web API and CLI

### 3.2 Out of Scope (For Now)

- Hotkey management via CLI (planned for future)
- Hotkey blacklisting (e.g. Windows hotkeys) — planned for future
- Custom AHK script management (planned for future)
- Runtime execution of AutoHotkey

---

## 4. Functional Overview

### 4.1 Core Capabilities

- CRUD for hotstrings (UI + CLI)
- CRUD for hotkeys (UI)
- Profile management (UI)
- Script generation per profile
- Script download via API and CLI

### 4.2 Interfaces

- Web UI (Blazor WebAssembly, PWA)
- REST API (ASP.NET Core)
- CLI (Console app that consumes the API)
- Shared DTO contracts (defined in the Application layer) consumed by API, UI and CLI to ensure parity, validation and versioning

---

## 5. High-Level Architecture

``` plaintext
┌─────────────────────────────┐
│ Blazor WASM PWA (MudBlazor) │
└──────────────┬──────────────┘
               │ HTTPS
┌──────────────▼──────────────┐
│ ASP.NET Core Web API        │
│ - Auth / Validation         │
│ - Command & Query Handling  │
└──────────────┬──────────────┘
               │
┌──────────────▼──────────────┐
│ Application / Core Layer    │
│ - Business Rules            │
│ - Commands & Queries        │
└──────────────┬──────────────┘
               │
┌──────────────▼──────────────┐
│ Infrastructure Layer        │
│ - EF Core                   │
│ - SQL Server provider       │
└─────────────────────────────┘

CLI ───────────────▶ API (same contracts as UI)
```

### 5.1 Architectural Principles

- Clear separation of concerns (thin controllers, service layers)
- Dependency inversion and DI-friendly boundaries
- API-first approach for UI and CLI parity
- Single source of truth (profiles & definitions)
- Infrastructure isolated from application logic for testability
- API contracts expressed as explicit DTOs in the Application layer to protect boundaries, enable validation, and support versioning

---

## 6. Logical Architecture

### 6.1 Frontend

Technology:

- Blazor WebAssembly (standalone)
- PWA
- MudBlazor component library

Responsibilities:

- Authentication & authorization UI
- User interaction and profile selection
- Orchestrate API calls and present results
- Download generated `.ahk` files

API Integration:

- **Typed HttpClient pattern** via single `IApiClient` interface (documented in Frontend CLAUDE.md)
- Configuration-driven base address
- Registered via `AddHttpClient<IInterface, Implementation>().AddStandardResilienceHandler()` in Program.cs
- Built-in resilience (retry, circuit breaker, timeout)

### 6.2 Backend – Web API

Characteristics:

- Controller-based API with thin controllers
- Command & Query separation (CQRS-style where appropriate)
- Explicit input models (DTOs) and shared validation

Capabilities:

- Hotstring management endpoints
- Hotkey management endpoints
- Profile management endpoints
- Script generation and download endpoints

Cross-cutting:

- Swagger / OpenAPI
- Problem Details (RFC 9457) for errors
- Structured logging (Serilog)

### 6.3 Application / Core Layer

Patterns:

- Commands & queries
- Single-responsibility services
- Explicit models and well-defined service boundaries
- DTOs live in this layer: input/output DTOs, mapping profiles, and shared validation rules (keeps API contract separate from domain and infrastructure)

Validation:

- FluentValidation shared between API and CLI

### 6.4 Infrastructure

- EF Core with SQL Server provider (code-first migrations)
- No repository pattern — handlers inject `DbContext` directly
- Integration tests use Testcontainers with real SQL Server (not in-memory database)

### 6.5 Command Line Interface (CLI)

Purpose:

- Power-user access for hotstring management and downloads

Characteristics:

- .NET Console App
- Uses the Web API (HTTPS) and the same contracts as UI
- Authentication via same identity model (MSAL / tokens) or CLI-specific flow

Examples:

```sh
# Create a new hotstring
ahkflowapp new "you're welcome" --profile work

# Search hotstrings
ahkflowapp list --profile work --grep "typo" --ignore-case

# Download a generated script
ahkflowapp download ahk --profile work
```

Notes:

- The CLI is intended to be scriptable and returns structured output (JSON option available) for piping into other tools.
- The CLI uses the same validation and contracts as the UI to keep behavior consistent.

---

## 7. Security & Identity

### 7.1 Authentication

- Azure Active Directory (Entra ID)
- MSAL for token acquisition in UI and CLI

### 7.2 Authorization

- Shared identity model across UI and CLI
- API-enforced access rules

---

## 8. Quality & Testing Strategy

### 8.1 Approach

- Test-Driven Development (TDD) encouraged
- Automated testing as a first-class concern

### 8.2 Test Types & Tools

- Unit tests: xUnit, FluentAssertions, NSubstitute (mocking)
- Integration tests: Testcontainers

---

## 9. Observability & Diagnostics

- Structured logging with Serilog
- Optional Azure Application Insights

---

## 10. Versioning & Code Quality

- MinVer for versioning
- EditorConfig for consistent coding standards
- Enforce naming and project structure conventions

---

## 11. DevOps & Deployment

### 11.1 Hosting

- Frontend: Azure Static Web Apps (PWA)
- Backend: Dockerized ASP.NET Core API (Azure App Service / AKS as desired)

### 11.2 CI/CD

- GitHub Actions workflows for automated deployment
- Automated pipeline: test → migrate database → deploy
- Separate workflows for frontend and backend

### 11.3 Configuration Management

AHKFlowApp follows Microsoft best practices for configuration:

**Frontend (Blazor WASM):**
- `appsettings.json` committed to git with production values (public, client-side, no secrets)
- Contains: Client ID, API URLs, public endpoints
- Local development overridden by `appsettings.Development.json` (ignored by git)
- Deployed automatically with Static Web Apps

**Backend (API):**
- `appsettings.Production.json` ignored by git (contains secrets)
- Template: `appsettings.Production.json.example` (safe to commit)
- Secrets managed via Azure App Service Configuration + Key Vault
- CI/CD workflow sets environment variables in Azure

**Rationale:**
- Blazor WASM runs in browser → all config is visible to users → secrets impossible
- OAuth Client ID is public by design (OAuth 2.0 specification)
- Backend secrets stored securely in Azure (App Service Config + Key Vault)

See: [Configuration Strategy](../development/configuration-strategy.md)

---

## 12. Development Workflow

### 12.1 Git Workflow

- GitHub Flow: feature branches from `main`, PR required for all merges
- Main branch as the single source of truth
- Branch naming: `feature/NNN-short-description`, `fix/short-description`

### 12.2 AI-Assisted Development

- Clear naming and intent
- Small, focused classes
- Predictable patterns
- This document is used as shared context for AI tooling

---

## 13. Next Documents in the Chain

This document feeds into:

- Product Backlog (Epics & User Stories)
- Functional Design (per feature)
- Technical Design (where required)
