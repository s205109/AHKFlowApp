@description('Base name prefix for all resources.')
param baseName string

@description('Target environment: test or prod.')
@allowed(['test', 'prod'])
param environment string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('Short deterministic suffix appended to globally-unique names to avoid collisions.')
param resourceToken string

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
var appName = '${baseName}-api-${environment}-${resourceToken}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: 'F1'
    tier: 'Free'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      appSettings: [
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
