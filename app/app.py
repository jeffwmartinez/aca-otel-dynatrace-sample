import logging
import os
import signal
import threading
import time
from datetime import datetime, timezone

from flask import Flask, jsonify, request
from opentelemetry import _logs as otel_logs
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter as OTLPLogExporterGRPC
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter as OTLPMetricExporterGRPC
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter as OTLPSpanExporterGRPC
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter as OTLPLogExporterHTTP
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter as OTLPMetricExporterHTTP
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter as OTLPSpanExporterHTTP
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Let ACA managed OpenTelemetry inject protocol/endpoint for local ingest.
OTEL_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
OTEL_PROTOCOL = os.environ.get("OTEL_EXPORTER_OTLP_PROTOCOL", "grpc")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "test")
PROOF_MARKER = os.environ.get("PROOF_MARKER", "ACA_PROOF_20260513_01")
PORT = int(os.environ.get("PORT", "8080"))

resource = Resource.create(
    {
        SERVICE_NAME: "aca-otel-dynatrace-app",
        SERVICE_VERSION: "1.1.0",
        "deployment.environment": ENVIRONMENT,
    }
)

# Log startup config immediately to stdout so it appears in ACA logs
print(f"[STARTUP] OTEL_ENDPOINT={OTEL_ENDPOINT}", flush=True)
print(f"[STARTUP] OTEL_PROTOCOL={OTEL_PROTOCOL}", flush=True)
_headers_raw = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
print(f"[STARTUP] OTEL_HEADERS_SET={'yes' if _headers_raw else 'NO - MISSING'}", flush=True)
print(f"[STARTUP] PROOF_MARKER={PROOF_MARKER}", flush=True)

# Enable OTEL SDK internal debug logging so export failures appear in logs
import logging as _stdlib_logging
_stdlib_logging.basicConfig(level=_stdlib_logging.WARNING)
_stdlib_logging.getLogger("opentelemetry").setLevel(_stdlib_logging.WARNING)
_stdlib_logging.getLogger("opentelemetry.sdk.trace.export").setLevel(_stdlib_logging.DEBUG)
_stdlib_logging.getLogger("opentelemetry.sdk._logs.export").setLevel(_stdlib_logging.DEBUG)
_stdlib_logging.getLogger("opentelemetry.sdk.metrics.export").setLevel(_stdlib_logging.DEBUG)

# Select exporter implementation based on protocol
# grpc: used when sending to managed agent (localhost:4317)
# http/protobuf: used when sending directly to Dynatrace OTLP endpoints
if OTEL_PROTOCOL == "http/protobuf":
    # HTTP exporters read OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS
    # from env vars automatically and append /v1/logs|metrics|traces to the base URL.
    # Do NOT pass endpoint= here — passing it bypasses the path-append logic.
    print(f"[STARTUP] Using HTTP exporters via env vars", flush=True)
    log_exporter = OTLPLogExporterHTTP()
    span_exporter = OTLPSpanExporterHTTP()
    metric_exporter = OTLPMetricExporterHTTP()
    print(f"[STARTUP] Log exporter endpoint: {log_exporter._endpoint}", flush=True)
    print(f"[STARTUP] Span exporter endpoint: {span_exporter._endpoint}", flush=True)
    print(f"[STARTUP] Metric exporter endpoint: {metric_exporter._endpoint}", flush=True)
else:
    exporter_kwargs = {"endpoint": OTEL_ENDPOINT}
    if OTEL_ENDPOINT.startswith("http://"):
        exporter_kwargs["insecure"] = True
    log_exporter = OTLPLogExporterGRPC(**exporter_kwargs)
    span_exporter = OTLPSpanExporterGRPC(**exporter_kwargs)
    metric_exporter = OTLPMetricExporterGRPC(**exporter_kwargs)

# Logs pipeline (short batch timeout to force immediate export)
log_provider = LoggerProvider(resource=resource)
log_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter, schedule_delay_millis=1000, export_timeout_millis=5000))
otel_logs.set_logger_provider(log_provider)

handler = LoggingHandler(level=logging.INFO, logger_provider=log_provider)
# basicConfig was already called above for OTEL debug; just add our handler to root
logging.getLogger().addHandler(handler)
logging.getLogger().addHandler(logging.StreamHandler())
logging.getLogger().setLevel(logging.INFO)
logger = logging.getLogger("aca-otel-dynatrace-app")

# Traces pipeline (short batch timeout)
trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(BatchSpanProcessor(span_exporter, schedule_delay_millis=1000, export_timeout_millis=5000))
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer("aca-otel-dynatrace-app")

# Metrics pipeline (1 second export interval)
metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=1000)
meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)
meter = metrics.get_meter("aca-otel-dynatrace-app")
request_counter = meter.create_counter("aca_otel.requests", description="Total HTTP requests")

shutdown = threading.Event()
app = Flask(__name__)


def heartbeat_worker() -> None:
    tick = 0
    while not shutdown.is_set():
        ts = datetime.now(timezone.utc).isoformat()
        logger.info(
            f"Heartbeat log {PROOF_MARKER}",
            extra={
                "app.component": "aca-otel-dynatrace-app",
                "timestamp": ts,
                "proof.marker": PROOF_MARKER,
            },
        )
        tick += 1
        if tick % 6 == 0:
            logger.warning(
                f"Sample warning {PROOF_MARKER}",
                extra={
                    "app.component": "aca-otel-dynatrace-app",
                    "timestamp": ts,
                    "proof.marker": PROOF_MARKER,
                },
            )
        time.sleep(5)


@app.route("/")
def index():
    proof = request.args.get("proof", PROOF_MARKER)
    with tracer.start_as_current_span("GET /") as span:
        span.set_attribute("http.method", "GET")
        span.set_attribute("http.route", "/")
        span.set_attribute("proof.marker", proof)
        request_counter.add(1, {"route": "/", "proof.marker": proof})
        logger.info(f"Handled request {proof}")
        response = jsonify(
            {
                "status": "ok",
                "service": "aca-otel-dynatrace-app",
                "proof": proof,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        )
    # Force immediate export after request
    log_provider.force_flush(timeout_millis=5000)
    trace_provider.force_flush(timeout_millis=5000)
    meter_provider.force_flush(timeout_millis=5000)
    return response


def handle_sigterm(*_):
    shutdown.set()
    try:
        trace_provider.shutdown()
    except Exception:
        pass
    try:
        meter_provider.shutdown()
    except Exception:
        pass
    try:
        log_provider.shutdown()
    except Exception:
        pass


signal.signal(signal.SIGTERM, handle_sigterm)

print(
    (
        f"Starting ACA OTel Dynatrace app. Exporting via {OTEL_PROTOCOL} to: {OTEL_ENDPOINT}. "
        f"Proof marker: {PROOF_MARKER}. Serving on port {PORT}."
    ),
    flush=True,
)

logger.info(
    f"App started. OTEL_ENDPOINT={OTEL_ENDPOINT}, SERVICE_NAME=aca-otel-dynatrace-app, PROOF={PROOF_MARKER}",
    extra={"app.component": "startup", "proof.marker": PROOF_MARKER},
)

threading.Thread(target=heartbeat_worker, daemon=True).start()
app.run(host="0.0.0.0", port=PORT)
