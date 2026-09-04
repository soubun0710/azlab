param location string = 'eastasia'
param staticWebAppName string
param staticWebAppResourceGroupName string = resourceGroup().name
param networkResourceGroupName string = 'azlab-jissou-network-rg'
param virtualNetworkName string = 'azlab-jissou-vnet'
param privateEndpointSubnetName string = 'azlab-jissou-pe-snet'
param privateEndpointName string = '${staticWebAppName}-pe'
param privateDnsZoneName string = 'privatelink.7.azurestaticapps.net'
param tags object = {}

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' existing = {
  name: staticWebAppName
  scope: resourceGroup(staticWebAppResourceGroupName)
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: virtualNetworkName
  scope: resourceGroup(networkResourceGroupName)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: privateEndpointSubnetName
  parent: virtualNetwork
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${staticWebAppName}-connection'
        properties: {
          privateLinkServiceId: staticWebApp.id
          groupIds: [
            'staticSites'
          ]
        }
      }
    ]
  }
  tags: tags
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: '${privateEndpoint.name}/default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'static-web-app-zone-config'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateDnsZoneId string = privateDnsZone.id
