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

- [ ] `AHKFlowDbContext` added and registered.
- [ ] A simple test entity exists to validate migrations.
- [ ] Migrations can be created and applied locally.
- [ ] Development profiles include LocalDB and Docker Compose SQL Server.
- [ ] Integration tests can run against SQL Server using Testcontainers.

## Out of scope

- Production scaling concerns.

## Notes / dependencies

- References 003 and 004.
