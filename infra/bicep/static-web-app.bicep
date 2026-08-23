param location string = 'eastus2'
param staticWebAppName string
param skuName string = 'Standard'
param skuTier string = 'Standard'
param tags object = {}

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
  tags: tags
}

output staticWebAppId string = staticWebApp.id
output defaultHostname string = staticWebApp.properties.defaultHostname
