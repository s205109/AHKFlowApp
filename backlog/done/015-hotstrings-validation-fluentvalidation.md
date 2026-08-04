# 015 - Hotstrings validation (FluentValidation)

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: API | CLI

## Summary

Implement and enforce validation rules for hotstring inputs using FluentValidation (shared where practical).

## User story

As a developer, I want shared validation so that API and CLI behavior is consistent and testable.

## Acceptance criteria

- [x] Hotstring create/update DTOs are validated with FluentValidation.
- [x] Validation is enforced by the API.
- [x] CLI surfaces validation failures in a user-friendly way. _(Satisfied by backlog 029 — shipped with the CLI.)_
- [x] Unit tests cover all validator rules and edge cases.
- [x] Integration tests verify validation errors surface as Problem Details from the API.

---

**Completed:** 2026-04-19 (PR #75; CLI AC deferred to 029)

## Out of scope

- Localization of messages.

## Notes / dependencies

- Used by 013 and 018.
