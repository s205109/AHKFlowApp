# 99 — Teardown

Stop paying for dev resources. Deletes the entire resource group, the SQL admin Entra group, and the GitHub secrets/variables.

> **⚠️ Destructive.** This deletes **everything** created by scripts 01 and 02. Only run this on a dev environment you're finished with. There is **no undo** — including the SQL database.

## Variables

```bash
ENVIRONMENT="dev"
BASE_NAME="ahkflow"
RESOURCE_GROUP="rg-${BASE_NAME}-${ENVIRONMENT}"
SQL_ADMIN_GROUP="${BASE_NAME}-sql-admins-${ENVIRONMENT}"
GITHUB_ORG="<your-github-username-or-org>"
GITHUB_REPO="AHKFlowApp"
```

## 1. Confirm

```bash
echo "About to delete resource group: $RESOURCE_GROUP"
read -p "Type the RG name to confirm: " CONFIRM
[ "$CONFIRM" = "$RESOURCE_GROUP" ] || { echo "Mismatch. Aborting."; exit 1; }
```

## 2. Delete Azure resources

```bash
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Resource group deletion started (async). Check status: az group show --name $RESOURCE_GROUP"
```

## 3. Delete the SQL admin Entra group

```bash
GROUP_ID=$(az ad group show --group "$SQL_ADMIN_GROUP" --query id -o tsv 2>/dev/null)
if [ -n "$GROUP_ID" ]; then
  az ad group delete --group "$GROUP_ID"
  echo "Deleted Entra group $SQL_ADMIN_GROUP"
fi
```

## 4. Clean up GitHub secrets and variables (optional)

```bash
for s in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_STATIC_WEB_APPS_API_TOKEN; do
  gh secret delete "$s" --repo "${GITHUB_ORG}/${GITHUB_REPO}" 2>/dev/null || true
done

for v in AZURE_RESOURCE_GROUP APP_SERVICE_NAME SQL_SERVER_NAME SQL_SERVER_FQDN SQL_DATABASE_NAME; do
  gh variable delete "$v" --repo "${GITHUB_ORG}/${GITHUB_REPO}" 2>/dev/null || true
done
```

## 5. Verify

```bash
az group show --name "$RESOURCE_GROUP" 2>&1 | grep -q "could not be found" && echo "✓ RG deleted" || echo "⚠ RG still exists (deletion may be async)"
```
