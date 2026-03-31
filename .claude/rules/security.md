---
alwaysApply: true
description: >
  Security best practices: secrets management, input validation, auth, transport, OWASP compliance.
---

# Security Rules

- Never hardcode secrets. Use `dotnet user-secrets` locally, Azure Key Vault in deployed environments.
- Never commit `.env` files, `appsettings.Development.json` with real credentials, or `credentials.json`.
- Validate all external input at system boundaries (FluentValidation / validation attributes).
- Parameterized queries only — never string concatenation for SQL. EF Core `$""` interpolation is safe; `ExecuteSqlRaw` with concatenation is not.
- Always add `[Authorize]` or `[AllowAnonymous]` explicitly on every controller/endpoint.
- HTTPS everywhere — enforce via HSTS, redirect HTTP to HTTPS.
- Data Protection API for encrypting user data at rest — never roll your own encryption.
- CORS: explicit origins only, never `AllowAnyOrigin()` in production.
