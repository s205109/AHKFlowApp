@description('Base name prefix for all resources.')
param baseName string

@description('Target environment: test or prod.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Resource ID of the runtime UAMI to assign to the App Service.')
param runtimeUamiId string

@description('Client ID of the runtime UAMI (used by DefaultAzureCredential).')
param runtimeUamiClientId string

@description('ASPNETCORE_ENVIRONMENT value for the App Service.')
param aspnetcoreEnvironment string

@description('Default hostname of the Static Web App frontend, used as an allowed CORS origin.')
param swaDefaultHostname string

@description('Entra ID instance URL. Defaults to the active cloud login endpoint.')
param azureAdInstance string = az.environment().authentication.loginEndpoint

@description('Entra ID tenant ID for token validation.')
param azureAdTenantId string

@description('Entra ID client ID (app registration) for token validation.')
param azureAdClientId string

var planName = '${baseName}-plan-${environment}'
var appName = '${baseName}-api-${environment}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeUamiId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|nginx:latest' // Placeholder — deploy-api.yml sets the real image
      alwaysOn: true
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://ghcr.io'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: runtimeUamiClientId
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: aspnetcoreEnvironment
        }
        {
          name: 'Cors__AllowedOrigins__0'
          value: 'https://${swaDefaultHostname}'
        }
        {
          name: 'AzureAd__Instance'
          value: azureAdInstance
        }
        {
          name: 'AzureAd__TenantId'
          value: azureAdTenantId
        }
        {
          name: 'AzureAd__ClientId'
          value: azureAdClientId
        }
      ]
    }
  }
}

output appServiceName string = appService.name
output appServiceDefaultHostname string = appService.properties.defaultHostName
