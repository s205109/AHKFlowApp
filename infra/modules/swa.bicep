@description('Base name prefix for all resources.')
param baseName string

@description('Target environment: test or prod.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region for resources. Note: Static Web Apps Free tier is only available in a subset of regions.')
param location string = resourceGroup().location

var swaName = '${baseName}-swa-${environment}'

resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: swaName
  location: location
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {}
}

output swaName string = swa.name
output swaDefaultHostname string = swa.properties.defaultHostname
