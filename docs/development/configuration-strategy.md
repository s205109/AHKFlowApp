# Configuration Management Strategy

This document explains how AHKFlowApp manages configuration for development and production environments, following Microsoft best practices for Blazor WebAssembly and ASP.NET Core applications.

## Overview

Different application layers require different configuration strategies:

| Layer | Strategy | Reason |
|-------|----------|--------|
| **Frontend (Blazor WASM)** | Production values in `appsettings.json` | Client-side, public, no secrets |
| **Backend (API)** | Use `.example` template + Azure App Service Configuration | Contains secrets (ConnectionStrings) |

---

## Frontend Configuration (Blazor WebAssembly)

### Strategy: Production Values in Base Config

**File:** `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/appsettings.json`

**Status:** ✅ Committed to repository (contains production values)

**Configuration pattern:**
- `appsettings.json` → Production values (deployed to Azure)
- `appsettings.Development.json` → Local development override (`localhost:7600`)

### Why This Works

Per [Microsoft documentation](https://learn.microsoft.com/aspnet/core/blazor/fundamentals/configuration?view=aspnetcore-10.0):

> **"Provide _public_ authentication configuration in an app settings file."**
>
> **"Configuration and settings files in the web root (`wwwroot` folder) are visible to users on the client, and users can tamper with the data. Don't store app secrets, credentials, or any other sensitive data in any web root file."**

**Key Points:**
- ✅ Blazor WASM runs entirely in the browser (client-side)
- ✅ All files are downloaded and visible in browser DevTools
- ✅ OAuth Client ID is **public by design** (OAuth 2.0 specification)
- ✅ API Base Address is **public** (visible in Network tab)
- ❌ Cannot contain secrets (browser code is always inspectable)

### Configuration Files

```
src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/
├── appsettings.json                     ✅ Committed (production values)
└── appsettings.Development.json         ❌ Ignored (local dev override with localhost)
```

### What's in Frontend Config

```json
{
  "AzureAd": {
    "ClientId": "18680edd-0d55-4280-a3a6-d0df5acd6c03",    // ✅ PUBLIC
    "Authority": "https://login.microsoftonline.com/...", // ✅ PUBLIC
    "ValidateAuthority": true                             // ✅ PUBLIC
  },
  "ApiHttpClient": {
    "BaseAddress": "https://ahkflowapp-api-dev.azurewebsites.net"  // ✅ PUBLIC
  },
  "Serilog": { ... }  // ✅ PUBLIC (logging config)
}
```

---

## Backend Configuration (ASP.NET Core API)

### Strategy: Azure App Service Configuration + Key Vault

**Template File:** `src/Backend/AHKFlowApp.API/appsettings.Production.json.example`

**Actual File:** `src/Backend/AHKFlowApp.API/appsettings.Production.json` → ❌ **IGNORED by git**

### Why This Must Be Secret

The backend configuration contains:
- ❌ SQL Connection Strings (with passwords)
- ❌ Database credentials
- ❌ Service-to-service secrets

These **must never be committed** to git.

### How Secrets Are Managed

**1. Local Development:**
- Copy `.example` file to create your local `appsettings.Production.json`
- Use fake/test values locally
- File is ignored by git (in `.gitignore`)

**2. Production (Azure):**
- Secrets stored in **Azure App Service Configuration**
- Connection strings reference **Azure Key Vault** using Managed Identity
- CI/CD workflow sets all values automatically

### Configuration Hierarchy

Azure App Service loads configuration in this order (later overrides earlier):

1. `appsettings.json` (base config)
2. `appsettings.Production.json` (if exists - ignored in our case)
3. **Azure App Service Configuration** ← ✅ **Our secrets live here**
4. Environment variables

**Result:** Secrets never touch git, managed securely in Azure.

---

## Summary: Best Practice Implementation

### ✅ Frontend (Blazor WASM)

| Aspect | Implementation |
|--------|---------------|
| **File** | `appsettings.json` |
| **Storage** | ✅ Committed to git |
| **Contains** | Public config only (Client ID, API URL) |
| **Why** | Client-side code is always visible to users |
| **Microsoft Docs** | "Provide _public_ authentication configuration in an app settings file" |

### ✅ Backend (API)

| Aspect | Implementation |
|--------|---------------|
| **File** | `appsettings.Production.json.example` (template) |
| **Storage** | ❌ NOT committed (in `.gitignore`) |
| **Contains** | Secrets (ConnectionStrings, credentials) |
| **Why** | Server-side secrets must never be public |
| **Production** | Azure App Service Configuration + Key Vault |

---

## Configuration Files Reference

```
src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/
├── appsettings.json                     ✅ Committed (production values)
└── appsettings.Development.json         ❌ Ignored (local dev override)

src/Backend/AHKFlowApp.API/
├── appsettings.json                     ✅ Base config
├── appsettings.Development.json         ❌ Ignored (local only)
├── appsettings.Production.json          ❌ Ignored (has secrets)
└── appsettings.Production.json.example  ✅ Template (safe)
```

### `.gitignore` Rules

```gitignore
# Local development only
**/appsettings.Development.json
**/appsettings.Local.json

# Backend production secrets - use Azure App Service Configuration
src/Backend/**/appsettings.Production.json

# Frontend: appsettings.json has production values (public, safe to commit)
# Frontend: appsettings.Development.json overrides for local development
```

---

## Local Development Setup

### Frontend

No setup needed — `appsettings.Development.json` is ignored but present locally, pointing to `localhost:7600`.

### Backend

```powershell
# Copy the example file
Copy-Item src/Backend/AHKFlowApp.API/appsettings.Production.json.example `
          src/Backend/AHKFlowApp.API/appsettings.Production.json

# Edit with your local values (or leave as-is for local development)
# This file is ignored by git
```

---

**Last Updated:** Based on Microsoft Blazor documentation for ASP.NET Core 10.0
