targetScope = 'resourceGroup'

@description('Azure region for shared resources such as Log Analytics, ACR, and identity.')
param location string = 'northcentralus'

@description('Azure region for the Container Apps environment and app.')
param containerAppsLocation string = 'northcentralusstage'

@description('Name of the Container App.')
param containerAppName string = 'dynatraceotel-app'

@description('Globally unique name for the Azure Container Registry (lowercase alphanumeric only, 5–50 chars).')
param containerRegistryName string

@description('Name of the Container Apps Environment.')
param containerAppsEnvironmentName string = 'dynatraceotel-env'

@description('Name of the Log Analytics Workspace.')
param logAnalyticsWorkspaceName string = 'dynatraceotel-logs'

@description('Container image name (without tag).')
param imageName string = 'dynatraceotel-app'

@description('Container image tag to deploy.')
param imageTag string = 'latest'

@description('OTEL service name.')
param otelServiceName string = 'dynatraceotel-app'

@description('Use user-assigned managed identity for ACR pull.')
param useManagedIdentityForAcr bool = true

var effectiveContainerAppsLocation = empty(containerAppsLocation) ? location : containerAppsLocation

var managedEnvironmentProperties = {
  appLogsConfiguration: {
    destination: 'log-analytics'
    logAnalyticsConfiguration: {
      customerId: logAnalyticsWorkspace.properties.customerId
      sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    }
  }
  environmentMode: 'WorkloadProfiles'
  workloadProfiles: [
    {
      name: 'Consumption'
      workloadProfileType: 'Consumption'
    }
  ]
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2026-03-02-preview' = {
  name: containerAppsEnvironmentName
  location: effectiveContainerAppsLocation
  properties: any(managedEnvironmentProperties)
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: !useManagedIdentityForAcr
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (useManagedIdentityForAcr) {
  name: '${containerAppName}-identity'
  location: location
}

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useManagedIdentityForAcr) {
  name: guid(containerRegistry.id, identity.id, acrPullRoleDefinitionId)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerApp 'Microsoft.App/containerApps@2026-03-02-preview' = {
  name: containerAppName
  location: effectiveContainerAppsLocation
  identity: useManagedIdentityForAcr
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${identity.id}': {}
        }
      }
    : null
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: useManagedIdentityForAcr
        ? [
            {
              server: containerRegistry.properties.loginServer
              identity: identity.id
            }
          ]
        : [
            {
              server: containerRegistry.properties.loginServer
              username: containerRegistry.listCredentials().username
              passwordSecretRef: 'acr-pull-password'
            }
          ]
      secrets: useManagedIdentityForAcr
        ? []
        : [
            {
              name: 'acr-pull-password'
              value: containerRegistry.listCredentials().passwords[0].value
            }
          ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: '${containerRegistry.properties.loginServer}/${imageName}:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'OTEL_SERVICE_NAME'
              value: otelServiceName
            }
            {
              name: 'OTEL_TRACES_EXPORTER'
              value: 'otlp'
            }
            {
              name: 'OTEL_METRICS_EXPORTER'
              value: 'otlp'
            }
            {
              name: 'OTEL_LOGS_EXPORTER'
              value: 'otlp'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
  dependsOn: useManagedIdentityForAcr
    ? [
        acrPullRoleAssignment
      ]
    : []
}

output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
