# 007 - Setup database foundation (EF Core + SQL Server provider)

## Metadata

- **Epic**: Initial project / solution
- **Type**: Feature
- **Interfaces**: API

## Summary

Setup Entity Framework Core with SQL Server provider end-to-end, including DbContext, migration wiring, and development profiles.

## User story

As a developer, I want a reliable database foundation so integration tests and data persistence work consistently across environments.

## Acceptance criteria

- [x] `AHKFlowDbContext` added and registered.
- [x] A simple test entity exists to validate migrations.
- [x] Migrations can be created and applied locally.
- [x] Development profiles include LocalDB and Docker Compose SQL Server.
- [x] Integration tests can run against SQL Server using Testcontainers.

## Out of scope

- Production scaling concerns.

## Notes / dependencies

- References 003 and 004.

---

**Completed:** 2026-04-29
