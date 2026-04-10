@description('Base name prefix for all resources.')
param baseName string

@description('Target environment: test or prod.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region for resources.')
param location string = resourceGroup().location

var deployerName = '${baseName}-uami-deployer-${environment}'
var runtimeName = '${baseName}-uami-runtime-${environment}'

resource deployerUami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deployerName
  location: location
}

resource runtimeUami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: runtimeName
  location: location
}

output deployerUamiName string = deployerUami.name
output deployerUamiId string = deployerUami.id
output deployerUamiClientId string = deployerUami.properties.clientId
output deployerUamiPrincipalId string = deployerUami.properties.principalId

output runtimeUamiName string = runtimeUami.name
output runtimeUamiId string = runtimeUami.id
output runtimeUamiClientId string = runtimeUami.properties.clientId
output runtimeUamiPrincipalId string = runtimeUami.properties.principalId
