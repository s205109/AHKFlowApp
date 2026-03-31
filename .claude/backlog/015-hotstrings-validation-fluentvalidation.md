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

- [ ] Hotstring create/update DTOs are validated with FluentValidation.
- [ ] Validation is enforced by the API.
- [ ] CLI surfaces validation failures in a user-friendly way.
- [ ] Unit tests cover all validator rules and edge cases.
- [ ] Integration tests verify validation errors surface as Problem Details from the API.

## Out of scope

- Localization of messages.

## Notes / dependencies

- Used by 013 and 018.
