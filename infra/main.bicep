targetScope = 'resourceGroup'

@description('Azure region for shared resources such as Log Analytics and ACR.')
param location string = 'northcentralus'

@description('Azure region for the Container Apps environment and app.')
param acaLocation string = 'northcentralusstage'

@description('Name of the Log Analytics workspace.')
param logAnalyticsName string = 'dynatraceotel-logs'

@description('Globally unique name for the Azure Container Registry.')
param acrName string = 'dynatraceotelacr'

@description('Name of the Container Apps environment.')
param acaEnvName string = 'dynatraceotel-env'

@description('Name of the Container App.')
param appName string = 'dynatraceotel-app'

@description('Base Dynatrace OTLP endpoint, for example https://tenant.live.dynatrace.com/api/v2/otlp.')
param dynatraceEndpoint string

@secure()
@description('Dynatrace ingest token with logs.ingest, metrics.ingest, and openTelemetryTrace.ingest scopes.')
param dynatraceApiKey string

var dynatraceAuthHeader = 'Api-Token ${dynatraceApiKey}'
var managedEnvironmentProperties = {
  appLogsConfiguration: {
    destination: 'log-analytics'
    logAnalyticsConfiguration: {
      customerId: logAnalytics.properties.customerId
      sharedKey: logAnalytics.listKeys().primarySharedKey
    }
  }
  openTelemetryConfiguration: {
    destinationsConfiguration: {
      otlpConfigurations: [
        {
          name: 'dynatrace-otlp-r2'
          endpoint: dynatraceEndpoint
          protocol: 'http'
          insecure: false
          headers: [
            {
              key: 'Authorization'
              value: dynatraceAuthHeader
            }
          ]
        }
      ]
    }
    logsConfiguration: {
      destinations: [
        'dynatrace-otlp-r2'
      ]
    }
    metricsConfiguration: {
      destinations: [
        'dynatrace-otlp-r2'
      ]
      includeKeda: false
    }
    tracesConfiguration: {
      destinations: [
        'dynatrace-otlp-r2'
      ]
      includeDapr: false
    }
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2026-03-02-preview' = {
  name: acaEnvName
  location: acaLocation
  properties: any(managedEnvironmentProperties)
}

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: acaLocation
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-pull-password'
        }
      ]
      secrets: [
        {
          name: 'acr-pull-password'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'dynatrace-api-key'
          value: dynatraceApiKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: appName
          image: '${acr.properties.loginServer}/${appName}:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'OTEL_SERVICE_NAME'
              value: appName
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
            {
              name: 'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL'
              value: 'http/protobuf'
            }
            {
              name: 'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT'
              value: '${dynatraceEndpoint}/v1/metrics'
            }
            {
              name: 'DYNATRACE_API_TOKEN'
              secretRef: 'dynatrace-api-key'
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
}

output containerAppUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
output containerRegistryLoginServer string = acr.properties.loginServer
