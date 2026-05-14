# Tutorial: Azure Container Apps to Dynatrace with OpenTelemetry

This tutorial walks through deploying the sample and validating telemetry.

## Prerequisites

- Azure subscription with permissions to deploy ACA resources
- Dynatrace SaaS environment
- Azure CLI with Container Apps extension
- Docker or ACR build workflow

## Dynatrace Environment Used In This Sample

- Environment home: https://lwh98919.live.dynatrace.com
- OTLP base endpoint: https://lwh98919.live.dynatrace.com/api/v2/otlp

## 1) Create a Dynatrace ingest token

Create a token in Dynatrace with these scopes:

- `logs.ingest`
- `metrics.ingest`
- `openTelemetryTrace.ingest`

Store the token securely. Do not commit it to source control.

## 2) Build and push the app image

From the `app/` folder:

```powershell
az acr build --registry <acr-name> --image dynatraceotel-app:v4 .
```

## 3) Deploy infrastructure

From repo root:

```powershell
az deployment group create \
  --resource-group <resource-group> \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  dynatraceEndpoint="https://lwh98919.live.dynatrace.com/api/v2/otlp" \
  dynatraceApiKey="<DYNATRACE_INGEST_TOKEN>"
```

## 4) Generate traffic

```powershell
$urlBase = "https://<your-container-app-url>"
1..20 | ForEach-Object { curl.exe -k -s -o NUL -w "%{http_code} " "$urlBase/" }
```

## 5) Validate in Dynatrace

Use broad checks first:

- Logs: `fetch logs | limit 20`
- Spans: `fetch spans | limit 20` or Distributed Traces UI
- Metrics: `aca_otel.requests.count`

Open the environment directly: https://lwh98919.live.dynatrace.com

## Known issue in this sample environment

Managed ACA forwarding is currently not visible in Dynatrace while direct app-to-Dynatrace export is successful. This sample is intentionally kept as-is for engineering investigation and reproducibility.
