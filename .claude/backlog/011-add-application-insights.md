# 011 - Add Application Insights

## Metadata

- **Epic**: Observability
- **Type**: Feature
- **Interfaces**: API

## Summary

Add Application Insights integration for production diagnostics after Azure infrastructure and CI/CD are in place.

## User story

As an operator, I want production telemetry in Azure so that I can diagnose failures and monitor behavior after deployment.

## Acceptance criteria

- [ ] API writes logs to Application Insights when configured.
- [ ] Connection string is environment-specific and not hardcoded.
- [ ] Local development still works without Application Insights.
- [ ] Deployment documentation includes required secret/configuration.

## Out of scope

- Custom dashboards and alerts.
- Frontend telemetry.

## Notes / dependencies

- Depends on 006 and 010.
- Requires Azure resources and GitHub secrets setup.
