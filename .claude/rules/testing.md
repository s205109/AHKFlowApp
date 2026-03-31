---
alwaysApply: true
description: >
  Enforces testing constraints to prevent common AI mistakes: InMemoryDatabase, mocking owned types, wrong naming.
---

# Testing Rules

- **Integration tests first** — WebApplicationFactory + Testcontainers catches serialization, middleware, DI, and query bugs.
- **Never `UseInMemoryDatabase`** — different behavior from real providers. Always use Testcontainers (SQL Server).
- **NSubstitute for third-party boundaries only** — don't mock what you own (no mocking DbContext, repositories, or internal services).
- Test naming: `MethodName_Scenario_ExpectedResult`.
- AAA pattern (Arrange/Act/Assert) with blank line separation; one assertion concept per test.
- Assert on `Result.IsSuccess` / `Result.Status` in handler unit tests.
- Shared fixtures: `IClassFixture<T>`, `ICollectionFixture<T>` for expensive setup (containers).
- Frameworks: xUnit, FluentAssertions, NSubstitute, Testcontainers.
