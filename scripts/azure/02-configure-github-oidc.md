# 02 — Configure GitHub OIDC + Azure

Wires up the OIDC trust between GitHub Actions and Azure. After this, the 4 workflows in `.github/workflows/` will be able to log into Azure with zero long-lived secrets.

Prerequisite: you have completed [`01-provision-azure.md`](./01-provision-azure.md) and still have the environment variables set.

> **Git Bash (MINGW64) users:** Run `export MSYS_NO_PATHCONV=1` (included in the Variables block below) or carry it over from script 01. See script 01 for the full explanation.

## Variables (continues from 01)

```bash
# Add these on top of the variables already set in script 01:
export MSYS_NO_PATHCONV=1  # Git Bash: carry over from script 01 or re-export here

GITHUB_ORG="<your-github-username-or-org>"
GITHUB_REPO="AHKFlowApp"

UAMI_DEPLOYER_CLIENT_ID=$(az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
UAMI_DEPLOYER_PRINCIPAL_ID=$(az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
UAMI_RUNTIME_PRINCIPAL_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE=$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)
KV_SCOPE=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
SQL_SERVER_FQDN="${SQL_SERVER_NAME}.database.windows.net"
```

## 1. Federated identity credentials on the deployer UAMI

One credential per GitHub trigger. The subject claim scopes each credential to an exact repo + branch/event combination.

```bash
az identity federated-credential create \
  --name "gh-${GITHUB_REPO}-main" \
  --identity-name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange" 2>/dev/null || echo "main credential exists"

az identity federated-credential create \
  --name "gh-${GITHUB_REPO}-pull-request" \
  --identity-name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request" \
  --audiences "api://AzureADTokenExchange" 2>/dev/null || echo "PR credential exists"
```

## 2. RBAC role assignments

The deployer UAMI gets `Contributor` on the resource group only — not the subscription. The runtime UAMI gets `Key Vault Secrets User` on the vault only. Deployer is added to the SQL admin group so it can alter schema.

```bash
# Deployer: Contributor on the resource group
az role assignment create \
  --role "Contributor" \
  --assignee-object-id "$UAMI_DEPLOYER_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$RG_SCOPE" 2>/dev/null || echo "Deployer role already assigned"

# Runtime: Key Vault Secrets User on the Key Vault
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$UAMI_RUNTIME_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$KV_SCOPE" 2>/dev/null || echo "Runtime KV role already assigned"

# Deployer: add to SQL admin group (gets full SQL admin via group membership)
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv)
az ad group member check --group "$GROUP_ID" --member-id "$UAMI_DEPLOYER_PRINCIPAL_ID" --query value -o tsv | grep -qi true || \
  az ad group member add --group "$GROUP_ID" --member-id "$UAMI_DEPLOYER_PRINCIPAL_ID"

echo "Waiting 30s for Entra group membership to propagate..."
sleep 30
```

## 3. Create SQL user for the runtime UAMI

**You** (the operator, a member of `$SQL_ADMIN_GROUP`) create a contained SQL user for the runtime UAMI and grant it least-privilege access.

### Option A — sqlcmd (requires `mssql-tools18` installed)

```bash
cat > /tmp/create-runtime-user.sql <<SQL
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$UAMI_RUNTIME_NAME')
BEGIN
  CREATE USER [$UAMI_RUNTIME_NAME] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [$UAMI_RUNTIME_NAME];
ALTER ROLE db_datawriter ADD MEMBER [$UAMI_RUNTIME_NAME];
GRANT EXECUTE TO [$UAMI_RUNTIME_NAME];
SQL

sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DATABASE_NAME" -G -i /tmp/create-runtime-user.sql
rm /tmp/create-runtime-user.sql
```

### Option B — Azure Portal Query Editor (no local sqlcmd needed)

1. Go to: `https://portal.azure.com/#@/resource${RG_SCOPE}/providers/Microsoft.Sql/servers/${SQL_SERVER_NAME}/databases/${SQL_DATABASE_NAME}/queryEditor`
2. Sign in with your Entra ID (the account that's a member of the admin group).
3. Paste and run:
   ```sql
   CREATE USER [ahkflowapp-uami-runtime-test] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [ahkflowapp-uami-runtime-test];
   ALTER ROLE db_datawriter ADD MEMBER [ahkflowapp-uami-runtime-test];
   GRANT EXECUTE TO [ahkflowapp-uami-runtime-test];
   ```
   (Replace `ahkflowapp-uami-runtime-test` with your actual `$UAMI_RUNTIME_NAME` if different.)

## 4. GitHub repo secrets

```bash
gh secret set AZURE_CLIENT_ID --body "$UAMI_DEPLOYER_CLIENT_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"

SWA_TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --query "properties.apiKey" -o tsv)
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body "$SWA_TOKEN" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

## 5. GitHub repo variables (non-secret)

```bash
gh variable set AZURE_RESOURCE_GROUP --body "$RESOURCE_GROUP" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set APP_SERVICE_NAME --body "$APP_SERVICE_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_SERVER_NAME --body "$SQL_SERVER_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_SERVER_FQDN --body "$SQL_SERVER_FQDN" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable set SQL_DATABASE_NAME --body "$SQL_DATABASE_NAME" --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

## 6. Configure App Service connection string

```bash
az webapp config connection-string set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --connection-string-type SQLAzure \
  --settings "DefaultConnection=Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

## 7. Configure CORS on the App Service

```bash
SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --query "defaultHostname" -o tsv)
az webapp cors add \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --allowed-origins "https://${SWA_HOSTNAME}"
```

## 8. First deploy + GHCR visibility flip

The first `deploy-api.yml` run will successfully push an image to GHCR (private by default) but the `deploy` job will fail with "manifest unknown" or "unauthorized" because App Service can't pull a private GHCR image without credentials.

After the first push, make the package public:

1. Visit the packages tab for your account type:
   - **Personal account:** `https://github.com/<your-username>?tab=packages`
   - **Organization:** `https://github.com/orgs/<your-org>/packages`
2. Find the `ahkflowapp-api` package.
3. Click **Package settings** → **Change visibility** → **Public** → confirm.
4. Re-run the failed `deploy` job: Actions → Deploy API → failed run → Re-run failed jobs.

The next run should succeed end-to-end.

> **Tighter alternative (future improvement):** keep GHCR private and configure App Service with a PAT that has `read:packages`. Or switch to Azure Container Registry and use the runtime UAMI with AcrPull.

## 9. Merge the PR and test the pipeline

### Step 1 — Verify all secrets and variables are set

```bash
gh secret list --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh variable list --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

Expected secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_STATIC_WEB_APPS_API_TOKEN`
Expected variables: `AZURE_RESOURCE_GROUP`, `APP_SERVICE_NAME`, `SQL_SERVER_NAME`, `SQL_SERVER_FQDN`, `SQL_DATABASE_NAME`

### Step 2 — Merge the PR

```bash
gh pr merge --squash --delete-branch --repo "${GITHUB_ORG}/${GITHUB_REPO}"
```

This triggers `deploy-api.yml` and `deploy-frontend.yml` on `main`.

### Step 3 — Watch the API deploy

```bash
# Get the run ID for the deploy-api workflow
gh run list --workflow=deploy-api.yml --repo "${GITHUB_ORG}/${GITHUB_REPO}" --limit 1

# Watch it (Ctrl-C to stop watching without cancelling the run)
gh run watch --repo "${GITHUB_ORG}/${GITHUB_REPO}" \
  $(gh run list --workflow=deploy-api.yml --repo "${GITHUB_ORG}/${GITHUB_REPO}" --limit 1 --json databaseId -q '.[0].databaseId')
```

**Expected on first run:**
- `build-test` ✓
- `build-push-image` ✓ — image pushed to GHCR (private by default)
- `migrate-db` ✓ — initial schema created in Azure SQL
- `deploy` ✗ — **fails** with "manifest unknown" or "unauthorized" (expected — GHCR is private)

### Step 4 — Flip GHCR package visibility to public

1. Go to your packages tab:
   - Personal account: `https://github.com/<your-username>?tab=packages`
   - Organization: `https://github.com/orgs/<your-org>/packages`
2. Find `ahkflowapp-api` → **Package settings** → **Change visibility** → **Public** → confirm.

### Step 5 — Re-run the failed deploy job

```bash
gh run rerun --failed --repo "${GITHUB_ORG}/${GITHUB_REPO}" \
  $(gh run list --workflow=deploy-api.yml --repo "${GITHUB_ORG}/${GITHUB_REPO}" --limit 1 --json databaseId -q '.[0].databaseId')
```

Watch it again — all 4 jobs should now be green.

### Step 6 — Verify the API is live

```bash
curl -fsS "https://${APP_SERVICE_NAME}.azurewebsites.net/health"
```

Expected: `Healthy` (or JSON `{"status":"Healthy",...}`).

If `$APP_SERVICE_NAME` is not set, use the literal URL:
```bash
curl -fsS "https://ahkflowapp-api-test.azurewebsites.net/health"
```

### Step 7 — Verify the frontend is live

```bash
SWA_HOSTNAME=$(az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostname -o tsv)
echo "Frontend: https://${SWA_HOSTNAME}"
```

Open the URL in a browser. The Blazor app should load and be able to reach the API (frontend `appsettings.json` points to `https://ahkflowapp-api-test.azurewebsites.net`).

---

**Done.** CI/CD is live.

**Teardown (when finished):** [`99-teardown.md`](./99-teardown.md)
