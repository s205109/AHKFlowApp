# Free-tier Azure migration plan

## Problem

The current Azure deployment model is built around a Linux custom-container API on App Service Basic (B1) and an Azure SQL Basic database. That design hardcodes paid SKUs and also depends on runtime capabilities that are not available on App Service Free (F1), especially custom containers, Always On, and the current managed-identity runtime pattern.

## Proposed approach

Move the backend to a free-tier-compatible shape:

1. Replace **container-based API deployment** with **code/package deployment** to App Service Free (F1) using the built-in ASP.NET Core runtime.
2. Replace **Azure SQL Basic** with the **Azure SQL free offer** using General Purpose serverless plus free-limit settings.
3. Remove **runtime managed-identity assumptions** from the hosted API path. Keep the GitHub OIDC and deployer identity path if it still works for provisioning and CI migrations.
4. Replace the runtime database connection strategy with **secret-based configuration**. Preferred path: keep Entra-authenticated SQL and use environment credentials via app settings; fallback path: SQL authentication only if the Entra secret-based runtime flow proves incompatible.
5. Remove or rewrite deployment features that only make sense for paid or container hosting.

## What stays supported

- CI build, tests, formatting, and coverage remain in **GitHub Actions** and are **not blocked by Azure free tiers**.
- Static Web App Free can stay as-is.
- Provisioning through Bicep plus PowerShell can stay, but the resource model and secrets/variables need to change.

## Features and behaviors to remove or change

- **Remove** Linux custom-container deployment (`GHCR` image deployment to App Service, `az webapp config container set`, Docker placeholder image wiring, `WEBSITES_PORT` runtime setting).
- **Remove** App Service runtime managed identity wiring from the free-tier backend path.
- **Remove** `AlwaysOn` assumptions; free tier will cold-start after idle.
- **Change** deployment health validation to tolerate cold starts or stop treating immediate post-deploy warmth as guaranteed.
- **Review** Application Insights plus Log Analytics separately; they are not required for free App Service or SQL, but they may still create cost outside this specific scope.

## Todos

1. **Choose runtime auth path**
   - Verify the preferred free-tier backend model: App Service F1 code deployment plus secret-based runtime configuration.
   - Prefer Entra-based runtime auth for SQL so SQL can stay Entra-only.
   - Define fallback to SQL auth only if the preferred approach is not viable.

2. **Refactor Azure infrastructure**
   - Update `infra/modules/web.bicep` to App Service Free (F1) and remove container and runtime-UAMI-specific settings.
   - Update `infra/modules/sql.bicep` to Azure SQL free-offer serverless settings.
   - Update `infra/main.bicep` outputs and parameters to match the new runtime model.
   - Decide whether monitoring resources stay, become optional, or are removed for stricter cost control.

3. **Replace API deployment workflow**
   - Rewrite `.github/workflows/deploy-api.yml` to publish and deploy the API as code/package deployment instead of building and deploying a GHCR container.
   - Remove container image metadata, build, push, and container-specific deployment steps.
   - Keep CI test/build gates and keep migration execution if it still works against Azure SQL free.

4. **Update provisioning scripts**
   - Rewrite `scripts/deploy.ps1` and `scripts/update.ps1` for code deployment.
   - Remove container and runtime-UAMI app settings.
   - Add whatever app settings and secrets are needed for the new runtime SQL auth path.
   - Revisit any post-deploy health probes that assume paid-tier warm behavior.

5. **Update application, configuration, and docs**
   - Verify the API can run correctly on App Service code deployment without container-specific settings.
   - Update environment docs, deployment docs, troubleshooting docs, and configuration references.
   - Remove or rewrite references to GHCR runtime pulls, Docker placeholder images, and runtime managed identity.

6. **Validate free-tier behavior**
   - Confirm the API deploys and starts on F1 with cold-start-tolerant checks.
   - Confirm SQL provisioning lands on the Azure SQL free offer and not on Basic.
   - Confirm migrations, frontend connectivity, auth, and health endpoints still work after the hosting change.

## Notes

- The current cost issue is **not caused by PR coverage**. Coverage runs in GitHub Actions and should remain unchanged.
- The biggest functional tradeoff is backend hosting behavior, not CI capability.
- Free App Service is expected to be slower and less predictable after idle periods because there is no Always On.
- This document is a plan only. Implementation has not started.
