# 020 - Hotstrings unit + integration tests

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: API

## Summary

Add unit and integration tests covering hotstring behavior end-to-end.

## User story

As a developer, I want tests for hotstrings so that changes can be made safely and regressions are caught early.

## Acceptance criteria

- [ ] Unit tests cover core hotstring rules (validation + generation-relevant constraints).
- [ ] Integration tests cover API endpoints against a real SQL Server database via Testcontainers.
- [ ] Tests run in CI.
- [ ] Tests include examples for reproducible database seeding and teardown in CI.

## Out of scope

- Full coverage targets.

## Notes / dependencies

- Depends on 004 and 013.
