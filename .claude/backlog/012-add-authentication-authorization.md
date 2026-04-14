# 012 - Add authentication and authorization

## Metadata

- **Epic**: Authentication and authorization
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Add authentication and authorization across UI, API, and CLI using Entra ID (Azure AD) and MSAL.

## User story

As a user, I want to sign in securely so that my profiles and automation definitions are protected.

## Acceptance criteria

- [x] UI authenticates via MSAL and calls the API with bearer tokens.
- [x] API validates tokens and enforces authorization.
- [x] Unauthorized/forbidden responses are consistent and documented.

## Out of scope

- Multiple identity providers.
- CLI authentication — deferred to 029. Tokens validated against `access_as_user` scope; no user DB persistence (claims-only via `ICurrentUser`).

## Notes / dependencies

- Impacts all feature endpoints.
- See `docs/architecture/authentication.md` and `docs/deployment/entra-setup.md`.
