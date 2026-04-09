# 00 — Prerequisites

Read this first. Install the required local tools, log into Azure and GitHub, and sanity-check your permissions. Once you are done here, continue to [`01-provision-azure.md`](./01-provision-azure.md).

## Required tools

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI | 2.60+ | https://learn.microsoft.com/cli/azure/install-azure-cli |
| GitHub CLI (`gh`) | 2.40+ | https://cli.github.com/ |
| .NET SDK | 10.0 (match `global.json`) | https://dotnet.microsoft.com/download |
| Docker Desktop (optional, for local image testing) | recent | https://www.docker.com/products/docker-desktop/ |
| `sqlcmd` or SQL Server Management Studio (for the SQL user creation step in script 02) | any | Windows: bundled with SSMS. macOS/Linux: `mssql-tools18` |

## Log in

```bash
az login
az account set --subscription "<your-subscription-id>"
az account show  # verify

gh auth login  # pick GitHub.com, HTTPS, web browser
gh auth status  # verify
```

## Permissions sanity check

You need these permissions in the target Azure subscription:

- Create resource groups, SQL servers, App Service plans, Key Vaults, Static Web Apps, user-assigned managed identities.
- Assign RBAC roles at resource-group scope (`Owner` or `User Access Administrator`).
- Create Entra ID security groups (Groups Administrator or higher in the tenant).

Quick check:

```bash
# Can you create resource groups in the target subscription?
az group list -o table

# Can you create Entra groups?
az ad group list --query "[0].displayName" -o tsv  # if this returns a name, you can read at minimum
```

If either fails, contact your tenant admin before proceeding.

## Azure Free Tier

Azure Free Tier covers most resources this setup creates. Notable cost items:

- **App Service Plan B1 Linux**: ~$13/month.
- **Azure SQL Basic**: ~$5/month (can downgrade to Free tier offer while available).
- **Everything else** (Key Vault, App Insights, SWA, UAMI, Log Analytics): free or sub-$1/month at dev volumes.

Budget ~$20/month for a single dev environment. Run `scripts/azure/99-teardown.md` to stop the meter when you're done.

---

**Next:** [`01-provision-azure.md`](./01-provision-azure.md)
