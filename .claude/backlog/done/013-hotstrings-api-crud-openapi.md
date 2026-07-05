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

- [x] Endpoints: create, update, delete, get-by-id, list-by-profile.
- [x] Endpoints are secured (see 012).
- [x] OpenAPI documents request/response models and auth requirements.
- [x] Unit tests cover controller/service behavior, including validation and business rules.
- [x] Integration tests exercise the API endpoints against a test database and verify auth and response shapes.

## Out of scope

- Bulk import/export.

## Notes / dependencies

- Depends on 003 and 012.

---

**Completed:** 2026-04-29
