# 006 - Add structured logging (Serilog)

## Metadata

- **Epic**: Logging
- **Type**: Feature
- **Interfaces**: API

## Summary

Add structured logging to the API using Serilog to support diagnostics and operations.

## User story

As a developer/operator, I want structured logs so that I can troubleshoot issues efficiently.

## Acceptance criteria

- [ ] Serilog is configured for the API.
- [ ] HTTP request logging is enabled with useful context (status code, path, duration).
- [ ] Sensitive data is not logged.
- [ ] Log configuration can be controlled per environment.

## Out of scope

- Application Insights integration (see 011).

## Notes / dependencies

- Complements CI/CD and future observability.
