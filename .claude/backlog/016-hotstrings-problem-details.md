# 016 - Hotstrings errors via Problem Details (RFC 9457)

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: API

## Summary

Return standardized errors from hotstring endpoints using RFC 9457 Problem Details.

## User story

As a client developer, I want consistent error responses so that UI and CLI can handle failures predictably.

## Acceptance criteria

- [ ] Validation errors return problem details with field-level information.
- [ ] Domain errors return problem details with stable types/titles.
- [ ] OpenAPI documents common error responses.
- [ ] Integration tests confirm validation and domain errors return RFC 9457 Problem Details with expected fields.
- [ ] Unit tests validate error mapping behavior for known domain exceptions.

## Out of scope

- A large custom error taxonomy.

## Notes / dependencies

- Applies to 013 (and later hotkey/profile endpoints too).
