# 009 - Setup Docker for development (Dockerfile + Docker Compose)

## Metadata

- **Epic**: Initial project / solution
- **Type**: Feature
- **Interfaces**: (N/A)

## Summary

Provide Dockerfile(s) and a `docker-compose.yml` for local development including a SQL Server instance.

## User story

As a developer, I want a reproducible development environment so onboarding and CI are consistent.

## Acceptance criteria

- [ ] Dockerfile for API exists.
- [ ] `docker-compose.yml` includes API and SQL Server for local development.
- [ ] Documentation shows how to run services locally with Docker.

## Out of scope

- Production container optimizations.

## Notes / dependencies

- Integrates with testing and DB foundation (004, 007).
