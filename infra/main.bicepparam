using './main.bicep'

// Required — set these before deploying
param environment = 'test'             // 'test' or 'prod'
param sqlAdminGroupId = ''             // az ad group show --group <name> --query id -o tsv
param sqlAdminGroupName = ''           // e.g. 'ahkflowapp-sql-admins-test'
param azureAdTenantId = ''             // from scripts/setup-entra-app.ps1 -Environment test
param azureAdClientId = ''             // from scripts/setup-entra-app.ps1 -Environment test

// Optional — change if needed
param baseName = 'ahkflowapp'
param location = 'westeurope'
