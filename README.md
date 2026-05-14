
# Azure Container Apps + OpenTelemetry + Dynatrace Sample

## What Is Not Working (Current Status)

- Managed ACA forwarding path is not delivering logs, metrics, or traces to Dynatrace in this environment.
- Direct app-to-Dynatrace export is working for all three signals.
- Current conclusion: app instrumentation and Dynatrace ingest are healthy; issue appears isolated to ACA managed forwarding.

This sample shows how to send OpenTelemetry telemetry from a Python app in Azure Container Apps (ACA) to Dynatrace.

## Azure Resources Used

- Subscription resource group: `jefmarti-otel-dynatrace-rg`
- Container Apps environment: `dynatraceotel-env`
- Container App: `dynatraceotel-app`
- Azure Container Registry: `dynatraceotelacr`
- Log Analytics workspace: `dynatraceotel-logs`
- Primary region: `northcentralus`
- Container Apps region: `northcentralusstage`

## Dynatrace Environment Links

- Environment home: https://lwh98919.live.dynatrace.com
- OTLP base endpoint: https://lwh98919.live.dynatrace.com/api/v2/otlp
- OTLP logs endpoint: https://lwh98919.live.dynatrace.com/api/v2/otlp/v1/logs
- OTLP metrics endpoint: https://lwh98919.live.dynatrace.com/api/v2/otlp/v1/metrics
- OTLP traces endpoint: https://lwh98919.live.dynatrace.com/api/v2/otlp/v1/traces

Use the Dynatrace environment home link above to open Logs and Distributed Traces in the UI for validation.

## Architecture Diagram

```mermaid
flowchart LR
	A[Python Flask App<br/>OTel SDK] --> B[ACA Managed OTel Agent]
	B --> C[Dynatrace OTLP Logs<br/>/api/v2/otlp/v1/logs]
	B --> D[Dynatrace OTLP Metrics<br/>/api/v2/otlp/v1/metrics]
	B --> E[Dynatrace OTLP Traces<br/>/api/v2/otlp/v1/traces]
```

## Current Issue (Important)

Current validation status:

- Direct app-to-Dynatrace mode: validated for logs, metrics, and traces.
- Managed ACA forwarding mode: app emits telemetry, but the same marker is not visible in Dynatrace.

Conclusion so far: app instrumentation and Dynatrace ingestion are working; issue appears isolated to managed ACA forwarding in this environment.

## Token Safety and Redaction

This repository does not contain real API tokens.

- Never commit real Dynatrace tokens.
- Use placeholders like `<DYNATRACE_INGEST_TOKEN>` in commands.
- Rotate/revoke any token that was ever exposed.

### How to Obtain a Dynatrace Ingest Token

1. In Dynatrace, go to Access tokens.
2. Create a token for OTLP ingest.
3. Minimum scopes for this sample:
   - `logs.ingest`
   - `metrics.ingest`
   - `openTelemetryTrace.ingest`
4. Copy the token once and store it securely (for example, Key Vault or your local secret store).

## Documentation

- Tutorial: [docs/tutorial.md](docs/tutorial.md)
- Architecture: [docs/architecture.md](docs/architecture.md)

## Repository Structure

- `app/` Python Flask app instrumented with OpenTelemetry SDK
- `infra/` Bicep templates for ACA environment and OTLP destinations
- `docs/` Tutorial and architecture notes
