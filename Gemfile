source "https://rubygems.org"

ruby "4.0.4"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Pagination
gem "pagy", "~> 9.0"

# Data-only migrations alongside schema migrations
gem "data_migrate"

# Structured single-line JSON request logs
gem "lograge"

# OpenTelemetry: traces, metrics, logs (env-driven exporter)
gem "opentelemetry-sdk"
gem "opentelemetry-instrumentation-all"
gem "opentelemetry-exporter-otlp"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

  gem "factory_bot_rails"
  gem "mocha"
  gem "webmock"
  gem "dotenv-rails"
end

group :development do
  gem "letter_opener"
  gem "foreman"
end
