# 013 - Hotstrings API CRUD + OpenAPI

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: API

## Summary

Provide REST endpoints for hotstring CRUD, fully described via Swagger/OpenAPI.

## User story

As a client (UI/CLI), I want a hotstring CRUD API so that hotstrings can be managed centrally.

## Acceptance criteria

- [ ] Endpoints: create, update, delete, get-by-id, list-by-profile.
- [ ] Endpoints are secured (see 012).
- [ ] OpenAPI documents request/response models and auth requirements.
- [ ] Unit tests cover controller/service behavior, including validation and business rules.
- [ ] Integration tests exercise the API endpoints against a test database and verify auth and response shapes.

## Out of scope

- Bulk import/export.

## Notes / dependencies

- Depends on 003 and 012.
