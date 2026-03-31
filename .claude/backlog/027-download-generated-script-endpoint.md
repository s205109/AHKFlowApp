# 027 - Download generated script endpoint

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: API

## Summary

Expose an authenticated endpoint to download the generated `.ahk` script for a given profile.

## User story

As a user, I want to download the generated script so that I can install/use it locally.

## Acceptance criteria

- [ ] Endpoint returns `.ahk` content with appropriate content type and download headers.
- [ ] Endpoint requires authentication/authorization (see 012).
- [ ] Endpoint enforces profile-scoped access.
- [ ] Integration tests verify content-type, content-disposition headers, authentication, and profile-scoped access.
- [ ] Unit tests for controller/handler logic around response headers and access checks.

## Out of scope

- Serving multiple script variants.

## Notes / dependencies

- Depends on 026.
