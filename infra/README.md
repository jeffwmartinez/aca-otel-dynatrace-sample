# Dynatrace ACA Managed OTEL Deployment

## Steps to Deploy

1. **Update Parameters:**
   - Edit `infra/main.parameters.json` (or `main.stage.parameters.json` for stage) with your Dynatrace OTLP endpoint and API key.

2. **Create Resource Group:**
   ```sh
   az group create -n jefmarti-otel-dynatrace-rg -l northcentralus
   ```

3. **Deploy Infrastructure:**
   ```sh
   az deployment group create \
     --resource-group jefmarti-otel-dynatrace-rg \
     --template-file infra/main.bicep \
     --parameters @infra/main.parameters.json
   ```

4. **Build and Push App Image:**
   - Build your Docker image:
     ```sh
     az acr build -r dynatraceotelacr -t dynatraceotel-app:latest ./app
     ```

5. **Verify Deployment:**
   - Confirm ACA environment and app are running in northcentralusstage.
   - Check that the managed OTEL agent is forwarding telemetry to Dynatrace.
   - Generate traffic and verify data in Dynatrace.

## Notes
- Do NOT set OTEL exporter endpoint/protocol/headers in the app spec.
- All OTEL destination config is at the ACA environment level.
- Only set OTEL_SERVICE_NAME and exporter selection vars in the app spec.
- For troubleshooting and validation flow, see `docs/tutorial.md` and `docs/architecture.md`.
