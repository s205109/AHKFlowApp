@description('Target environment.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Base name prefix for all resources.')
param baseName string = 'ahkflowapp'

@description('Object ID of the Entra security group that will be the SQL admin.')
param sqlAdminGroupId string

@description('Display name of the Entra security group that will be the SQL admin.')
param sqlAdminGroupName string

var aspnetcoreEnvironment = environment == 'prod' ? 'Production' : 'Test'

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    baseName: baseName
    environment: environment
    location: location
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    baseName: baseName
    environment: environment
    location: location
    sqlAdminGroupId: sqlAdminGroupId
    sqlAdminGroupName: sqlAdminGroupName
  }
}

module web 'modules/web.bicep' = {
  name: 'web'
  params: {
    baseName: baseName
    environment: environment
    location: location
    runtimeUamiId: identity.outputs.runtimeUamiId
    runtimeUamiClientId: identity.outputs.runtimeUamiClientId
    aspnetcoreEnvironment: aspnetcoreEnvironment
  }
}

module swa 'modules/swa.bicep' = {
  name: 'swa'
  params: {
    baseName: baseName
    environment: environment
    location: location
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    baseName: baseName
    environment: environment
    location: location
  }
}

// Identity outputs
output deployerUamiName string = identity.outputs.deployerUamiName
output deployerUamiId string = identity.outputs.deployerUamiId
output deployerUamiClientId string = identity.outputs.deployerUamiClientId
output deployerUamiPrincipalId string = identity.outputs.deployerUamiPrincipalId
output runtimeUamiName string = identity.outputs.runtimeUamiName
output runtimeUamiId string = identity.outputs.runtimeUamiId
output runtimeUamiClientId string = identity.outputs.runtimeUamiClientId
output runtimeUamiPrincipalId string = identity.outputs.runtimeUamiPrincipalId

// SQL outputs
output sqlServerName string = sql.outputs.sqlServerName
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output sqlDatabaseName string = sql.outputs.sqlDatabaseName

// Web outputs
output appServiceName string = web.outputs.appServiceName
output appServiceDefaultHostname string = web.outputs.appServiceDefaultHostname

// SWA outputs
output swaName string = swa.outputs.swaName
output swaDefaultHostname string = swa.outputs.swaDefaultHostname

// Monitoring outputs
output appInsightsName string = monitoring.outputs.appInsightsName
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
