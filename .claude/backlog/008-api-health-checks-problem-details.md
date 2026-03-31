# 008 - Setup API health checks and Problem Details (RFC 9457)

## Metadata

- **Epic**: Initial project / solution
- **Type**: Feature
- **Interfaces**: API

## Summary

Add health checks, Swagger/OpenAPI, and global error handling using Problem Details (RFC 9457).

## User story

As an operator, I want health endpoints and consistent error responses so that services are observable and clients can handle errors predictably.

## Acceptance criteria

- [ ] Health endpoints implemented and include database connectivity checks.
- [ ] Swagger/OpenAPI available in development.
- [ ] Global error handling returns RFC 9457 Problem Details.
- [ ] Integration tests cover health and Problem Details behavior.

## Out of scope

- Advanced observability integrations.

## Notes / dependencies

- Complements 007 and 010.
