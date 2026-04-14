# 029 - CLI authentication

## Metadata

- **Epic**: Authentication and authorization
- **Type**: Feature
- **Interfaces**: CLI
- **Depends on**: 017-scaffold-cli-project, 012-add-authentication-authorization

## Summary

Add Entra ID authentication to the CLI tool using MSAL.NET device-code flow. The CLI will acquire a bearer token and pass it to all API calls.

## User story

As a user, I want to sign in to the CLI so that my hotstrings are protected and associated with my account.

## Acceptance criteria

- [ ] `ahkflow login` triggers device-code flow and caches the token.
- [ ] Cached token is attached to all subsequent API calls.
- [ ] `ahkflow logout` clears the cached token.
- [ ] Expired tokens are refreshed silently; user is prompted to re-login on failure.

## Out of scope

- Multiple identity providers.

## Notes / dependencies

- Uses the same Entra app registration created by `scripts/setup-entra-app.ps1` — no new app registration needed.
- Add a public-client redirect URI (`http://localhost`) to the existing registration.
- Scope: `api://{clientId}/access_as_user` (same as UI).
- See `docs/architecture/authentication.md` for the overall auth architecture.
