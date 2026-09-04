targetScope = 'resourceGroup'

param location string = 'eastus2'
param privateEndpointLocation string = 'japaneast'
param staticWebAppName string = 'azlab-jissou-swa'
param networkResourceGroupName string = 'azlab-jissou-network-rg'
param virtualNetworkName string = 'azlab-jissou-vnet'
param privateEndpointSubnetName string = 'azlab-jissou-pe-snet'
param privateEndpointName string = '${staticWebAppName}-pe'
param privateDnsZoneName string = 'privatelink.7.azurestaticapps.net'
param tags object = {}

module staticWebApp './static-web-app.bicep' = {
  name: 'deploy-${staticWebAppName}'
  params: {
    location: location
    staticWebAppName: staticWebAppName
    tags: tags
  }
}

module staticWebAppPrivateEndpoint './static-web-app-private-endpoint.bicep' = {
  name: 'deploy-${privateEndpointName}'
  dependsOn: [
    staticWebApp
  ]
  params: {
    location: privateEndpointLocation
    staticWebAppName: staticWebAppName
    staticWebAppResourceGroupName: resourceGroup().name
    networkResourceGroupName: networkResourceGroupName
    virtualNetworkName: virtualNetworkName
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointName: privateEndpointName
    privateDnsZoneName: privateDnsZoneName
    tags: tags
  }
}

output staticWebAppId string = staticWebApp.outputs.staticWebAppId
output privateEndpointId string = staticWebAppPrivateEndpoint.outputs.privateEndpointId
output privateDnsZoneId string = staticWebAppPrivateEndpoint.outputs.privateDnsZoneId
