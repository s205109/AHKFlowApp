@description('Base name prefix for all resources.')
param baseName string

@description('Target environment: test or prod.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Object ID of the Entra security group that will be the SQL admin.')
param sqlAdminGroupId string

@description('Display name of the Entra security group that will be the SQL admin.')
param sqlAdminGroupName string

var serverName = '${baseName}-sql-${environment}'
var databaseName = '${baseName}-db'

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    // Entra-only authentication — no SQL admin password
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlAdminGroupName
      sid: sqlAdminGroupId
      tenantId: tenant().tenantId
      principalType: 'Group'
    }
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    // Local backup redundancy keeps costs low for non-production
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Allow Azure services to reach the server (needed for App Service → SQL via Managed Identity)
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
