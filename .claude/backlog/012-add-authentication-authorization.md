# 012 - Add authentication and authorization

## Metadata

- **Epic**: Authentication and authorization
- **Type**: Feature
- **Interfaces**: UI | API | CLI

## Summary

Add authentication and authorization across UI, API, and CLI using Entra ID (Azure AD) and MSAL.

## User story

As a user, I want to sign in securely so that my profiles and automation definitions are protected.

## Acceptance criteria

- [ ] UI authenticates via MSAL and calls the API with bearer tokens.
- [ ] API validates tokens and enforces authorization.
- [ ] CLI supports a sign-in flow appropriate for a console app.
- [ ] Unauthorized/forbidden responses are consistent and documented.

## Out of scope

- Multiple identity providers.

## Notes / dependencies

- Impacts all feature endpoints.
