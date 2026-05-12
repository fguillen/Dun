if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? && !Rails.env.test?
  require "opentelemetry/sdk"
  require "opentelemetry/instrumentation/all"
  require "opentelemetry/exporter/otlp"

  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "dun-backend")
    c.use_all
  end
end
