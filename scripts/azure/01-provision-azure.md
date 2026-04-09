# 01 — Provision Azure resources

This runbook stands up the full Azure environment for a single environment (default: `dev`). All `az X create` calls are idempotent (preceded by `az X show ...`). Re-running a section is safe.

Prerequisite: you have completed [`00-prerequisites.md`](./00-prerequisites.md) and run `az login`.

> **Git Bash (MINGW64) users:** Git Bash converts paths starting with `/` to Windows paths (e.g. `/subscriptions/...` → `C:/Program Files/Git/subscriptions/...`). This breaks both ARM ID captures *and* ARM ID arguments to `az`. The fix: run `export MSYS_NO_PATHCONV=1` once at the start of your shell session (included in the Variables block below). PowerShell (`pwsh`) has no path mangling and needs no workaround.

## Variables

Set these once at the top of your shell. Re-export them if you open a new terminal. To provision a `prod` environment later, set `ENVIRONMENT=prod` and re-run everything.

```bash
export MSYS_NO_PATHCONV=1  # Git Bash: prevents /subscriptions/... paths being mangled to C:/Program Files/Git/...

ENVIRONMENT="dev"                                      # dev | prod
LOCATION="westeurope"                                  # any Azure region
BASE_NAME="ahkflowapp"                                    # project prefix

RESOURCE_GROUP="rg-${BASE_NAME}-${ENVIRONMENT}"
SQL_SERVER_NAME="${BASE_NAME}-sql-${ENVIRONMENT}"
SQL_DATABASE_NAME="${BASE_NAME}-db"
KEY_VAULT_NAME="${BASE_NAME}-kv-${ENVIRONMENT}"
APP_SERVICE_PLAN="${BASE_NAME}-plan-${ENVIRONMENT}"
APP_SERVICE_NAME="${BASE_NAME}-api-${ENVIRONMENT}"
SWA_NAME="${BASE_NAME}-swa-${ENVIRONMENT}"
LAW_NAME="${BASE_NAME}-logs-${ENVIRONMENT}"
APP_INSIGHTS_NAME="${BASE_NAME}-insights-${ENVIRONMENT}"
UAMI_DEPLOYER_NAME="${BASE_NAME}-uami-deployer-${ENVIRONMENT}"
UAMI_RUNTIME_NAME="${BASE_NAME}-uami-runtime-${ENVIRONMENT}"
SQL_ADMIN_GROUP="${BASE_NAME}-sql-admins-${ENVIRONMENT}"
```

## 1. Register resource providers

```bash
for ns in Microsoft.Web Microsoft.Sql Microsoft.KeyVault \
          Microsoft.OperationalInsights Microsoft.Insights \
          Microsoft.ManagedIdentity; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)
  if [ "$state" != "Registered" ]; then
    echo "Registering $ns..."
    az provider register --namespace "$ns" >/dev/null
  else
    echo "$ns already registered"
  fi
done
```

## 2. Resource group

```bash
az group show --name "$RESOURCE_GROUP" &>/dev/null || \
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
```

## 3. Log Analytics workspace + Application Insights

```bash
az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" --workspace-name "$LAW_NAME" &>/dev/null || \
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LAW_NAME" \
  --location "$LOCATION"

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" --workspace-name "$LAW_NAME" --query id -o tsv)

az monitor app-insights component show \
  --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az monitor app-insights component create \
  --app "$APP_INSIGHTS_NAME" \
  --location "$LOCATION" \
  --resource-group "$RESOURCE_GROUP" \
  --workspace "$LAW_ID"
```

## 4. Entra security group for SQL admin

```bash
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv 2>/dev/null)
if [ -z "$GROUP_ID" ]; then
  GROUP_ID=$(az ad group create \
    --display-name "$SQL_ADMIN_GROUP" \
    --mail-nickname "$SQL_ADMIN_GROUP" \
    --query id -o tsv)
  echo "Created group $SQL_ADMIN_GROUP ($GROUP_ID)"
fi

# Add yourself so you can create SQL users in script 02
ME_ID=$(az ad signed-in-user show --query id -o tsv)
az ad group member check --group "$GROUP_ID" --member-id "$ME_ID" --query value -o tsv | grep -qi true || \
  az ad group member add --group "$GROUP_ID" --member-id "$ME_ID"
```

## 5. Azure SQL server + database (Entra-only auth)

```bash
az sql server show --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az sql server create \
  --name "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "$SQL_ADMIN_GROUP" \
  --external-admin-sid "$GROUP_ID"

az sql db show \
  --name "$SQL_DATABASE_NAME" \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az sql db create \
  --name "$SQL_DATABASE_NAME" \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --service-objective Basic \
  --backup-storage-redundancy Local

# Allow Azure services (required for App Service to reach SQL via Active Directory Default)
az sql server firewall-rule show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowAllAzureServices &>/dev/null || \
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowAllAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Allow your current IP so you can create SQL users in script 02
MY_IP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name "operator-${USER}-$(date +%s)" \
  --start-ip-address "$MY_IP" \
  --end-ip-address "$MY_IP"
```

## 6. Key Vault

```bash
az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az keyvault create \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku standard \
  --enable-rbac-authorization true

# Assign yourself Secrets Officer so you can manage secrets
KV_SCOPE=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$ME_ID" \
  --scope "$KV_SCOPE" 2>/dev/null || echo "Role already assigned"
```

## 7. App Service plan (Linux B1)

```bash
az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku B1 \
  --is-linux
```

## 8. User-assigned managed identities

```bash
az identity show --name "$UAMI_DEPLOYER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az identity create \
  --name "$UAMI_DEPLOYER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az identity create \
  --name "$UAMI_RUNTIME_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION"

UAMI_RUNTIME_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
UAMI_RUNTIME_CLIENT_ID=$(az identity show --name "$UAMI_RUNTIME_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
```

## 9. App Service (Linux container)

```bash
az webapp show --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az webapp create \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --container-image-name "nginx:latest"
# ^ nginx is a throwaway placeholder. deploy-api.yml sets the real image on first deploy.

# Attach the runtime UAMI
az webapp identity assign \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --identities "$UAMI_RUNTIME_ID"

# Tell DefaultAzureCredential which identity to use
az webapp config appsettings set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "AZURE_CLIENT_ID=$UAMI_RUNTIME_CLIENT_ID" \
    "WEBSITES_PORT=8080" \
    "ASPNETCORE_ENVIRONMENT=Production"
```

## 10. Static Web App (Free tier)

```bash
az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null || \
az staticwebapp create \
  --name "$SWA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Free
# Note: Static Web Apps Free tier is only available in a limited set of regions.
# If this fails with "location not supported", retry with one of:
#   westeurope, westus2, centralus, eastus2, eastasia
# The Free tier is content-only, so the region mainly affects cold-start latency.
# Full list: https://learn.microsoft.com/azure/static-web-apps/overview#regions
```

## 11. Summary — copy these for script 02

```bash
echo ""
echo "=== Provisioning complete. Save these for script 02: ==="
echo "RESOURCE_GROUP=$RESOURCE_GROUP"
echo "SQL_SERVER_NAME=$SQL_SERVER_NAME"
echo "SQL_SERVER_FQDN=${SQL_SERVER_NAME}.database.windows.net"
echo "SQL_DATABASE_NAME=$SQL_DATABASE_NAME"
echo "KEY_VAULT_NAME=$KEY_VAULT_NAME"
echo "APP_SERVICE_NAME=$APP_SERVICE_NAME"
echo "SWA_NAME=$SWA_NAME"
echo "UAMI_DEPLOYER_NAME=$UAMI_DEPLOYER_NAME"
echo "UAMI_RUNTIME_NAME=$UAMI_RUNTIME_NAME"
echo "SQL_ADMIN_GROUP=$SQL_ADMIN_GROUP"
echo ""
echo "Tenant ID: $(az account show --query tenantId -o tsv)"
echo "Subscription ID: $(az account show --query id -o tsv)"
```

> **Entra app registrations are NOT created here.** The API runs without auth enforcement until backlog item 012 wires up Entra ID authentication. This runbook only builds the infrastructure needed to deploy a container.

---

**Next:** [`02-configure-github-oidc.md`](./02-configure-github-oidc.md)
