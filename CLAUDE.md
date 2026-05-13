# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`dun` is an API-only Rails 8 backend for an async multiplayer medieval-fantasy strategy game designed for developers during workday micro-idle moments. The CLI client and any future integrations consume the JSON API exposed by this backend.

- **Product overview**: [PRODUCT.md](PRODUCT.md) — what the game is, who it's for, core mechanics at a glance.
- **Game mechanics source of truth**: [docs/dun Game Design Document.v3.md](docs/dun%20Game%20Design%20Document.v3.md). Section refs like `§17.1` point at that doc.
- **HTTP API contract**: [docs/openapi.yaml](docs/openapi.yaml) — OpenAPI 3.1 spec covering everything implemented so far. The CLI gem and any future integration consume only this surface.
- **Implementation roadmap**: [TODO.md](TODO.md). Phase 1 (Identity, Auth, Server Membership) is complete; Phase 2 (World Lifecycle & Map Generation) is next.

## Stack

- **Ruby**: 4.0.4
- **Rails**: 8.1.3 (`--api` mode)
- **Database**: PostgreSQL 18+
- **Background jobs**: Solid Queue (Active Job adapter)
- **Cache**: Solid Cache
- **Pub/Sub**: Solid Cable (available if needed post-v1)
- **Auth**: magic link + 90-day Bearer `ApiKey` for both user kinds (Player at `/v1/auth/...`, Admin at `/v1/admin/auth/...`). `MagicLink` and `ApiKey` are polymorphic on `owner` (`Player` or `Admin`).
- **Pagination**: [pagy](https://github.com/ddnexus/pagy)
- **Data migrations**: [data_migrate](https://github.com/ilyakatz/data-migrate)
- **Logs**: [lograge](https://github.com/roidrage/lograge) JSON formatter
- **Tracing/metrics**: OpenTelemetry SDK + auto-instrumentation (env-driven exporter)
- **Testing**: Minitest + Mocha + WebMock
- **Factories**: Factory Bot (no fixtures — factories in `test/factories/`)
- **Dev mail**: `letter_opener` (deferred provider decision — see §17.1 follow-up)

## Development

```bash
bin/dev                  # starts web + jobs (Solid Queue worker) via foreman
bin/rails db:migrate     # schema migrations
bin/rails data:migrate   # data migrations (data_migrate gem)
bin/rails test           # full suite (parallel)
bin/rails test test/models/example_test.rb                           # single file
bin/rails test test/services/example_service_test.rb -n test_name    # single test
```

## Architecture

### Routes & response shape

All routes mount under `/v1/...`. The player surface is at the root of that namespace; admin endpoints sit under `/v1/admin/...`. Responses are JSON-only. Error responses use the envelope:

```json
{ "error": { "code": "string_code", "message": "human readable", "retry_after": 30 } }
```

`retry_after` is included only on rate-limit (`429`) responses. Every response also echoes `X-Request-Id` (auto-generated if absent), which appears in lograge JSON logs and OpenTelemetry traces.

The full request/response surface is captured in [docs/openapi.yaml](docs/openapi.yaml) (OpenAPI 3.1). When adding or changing endpoints, update that file in the same commit.

### Base controllers

- `Api::BaseController` — inherits `ActionController::API`. Enforces player-scope Bearer auth via the `Api::Authentication` concern, populates `Current.player` and `Current.api_key`, normalizes error rendering.
- `Api::Admin::BaseController` — inherits `Api::BaseController`, swaps the auth concern for `Api::Admin::Authentication`, populates `Current.admin` instead.

A player-scope ApiKey presented at an admin endpoint 401s, and vice versa.

### Services

Service objects live under `app/services/`. Keep controllers thin; business logic that spans multiple models lives in service objects. Conventional shape: `MyService.call(...)` returning a model, result struct, or raising a domain-specific error class nested under the service.

### Data migrations

Uses the `data_migrate` gem for data-only changes (separate from schema migrations). Data migrations live in `db/data/` and are tracked in `db/data_schema.rb`. Use `bin/rails generate data_migration <name>` to create one. For backfills, prefer calling existing service objects over raw SQL.

### Seed data

`db/seeds.rb` is idempotent. Bootstrap secrets (admin email, admin name, magic-link from-address) come from `ENV.fetch(...)` — no fallbacks; missing envs fail loudly.

### Testing conventions

- Framework: Minitest + Mocha + FactoryBot + WebMock
- Use Factory Bot (`create`, `build`) — do NOT use fixtures
- Mock HTTP with WebMock; `WebMock.disable_net_connect!(allow_localhost: true)` is set in `test/test_helper.rb`
- Controller tests: use the helper at `test/test_helpers/session_test_helper.rb` exposing `authenticate_as_player(player)` and `authenticate_as_admin(admin)` (both set the `Authorization: Bearer ...` header)
- Parallel runner enabled (`parallelize(workers: :number_of_processors)`)

### Workflow Requirements

- Tests: Always write controller/model tests that confirm the proper function of any added or changed feature. Tests must pass before the work is considered done.
- Commit: Always create a git commit at the end of each task.
- Bug fix: Always write a test that reproduces the issue before fixing it.
- Documentation: Always use context7 when you need code generation, setup, configuration steps, ruby gem documentation, or library/API documentation.
- Ask the user: in case of doubts always ask the user for clarifications.

## Auth

Two AR models — `Player` and `Admin` — each only carrying `(email, name, timestamps)`. They share an auth substrate via two polymorphic tables:

- `MagicLink` — `(owner_type, owner_id, email, token_digest, expires_at, consumed_at)`. 15-minute expiry, single-use. The raw token is shown once; the DB stores SHA-256 digest only.
- `ApiKey` — `(owner_type, owner_id, name, token_digest, last_used_at, expires_at, revoked_at)`. 90-day rolling expiry — refreshed on each authenticated request. Revocable.

Auth flow (parallel for Player and Admin):

1. `POST /v1/auth/magic_link` (or `/v1/admin/auth/magic_link`) — caller submits email, mailer enqueues a magic link.
2. Click → `POST /v1/auth/exchange` (or `/v1/admin/auth/exchange`) — caller submits raw token, receives `{api_key, expires_at}`.
3. Subsequent requests carry `Authorization: Bearer <api_key>`.

`Current` (`ActiveSupport::CurrentAttributes`) carries `player`, `admin`, `api_key`, `request_id` for the request lifecycle.

A single human who is both a player and an admin signs in once on each surface and the CLI stores both ApiKeys.

## Code style

- Keep controllers thin; business logic in models or service objects under `app/services/`
- Dates always in format `YYYY-MM-DD`
- `snake_case` for all field and method names (Rails convention)
