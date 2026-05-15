# 01 — Foundations

Phase 0 of [TODO.md](../../TODO.md). The pieces installed before any domain feature: stack, request envelope, auth substrate hooks, observability, identifiers, data migrations.

If you are debugging a "why does the request look like this?" question, this is the file.

---

## Stack at a glance

| Layer | Choice | Why |
|---|---|---|
| Runtime | Ruby 4.0.4 | Per §17.5 of the GDD |
| Framework | Rails 8.1.3 `--api` | JSON-only; no views, no asset pipeline |
| DB | PostgreSQL 18+ | citext for case-insensitive emails/handles, jsonb everywhere |
| Background jobs | Solid Queue (Active Job adapter) | DB-backed, no Redis |
| Cache | Solid Cache | DB-backed |
| Pub/sub | Solid Cable (available, unused so far) | DB-backed |
| Pagination | [pagy](https://github.com/ddnexus/pagy) | Lightweight; lazy-loaded |
| Logs | [lograge](https://github.com/roidrage/lograge) JSON formatter | One structured line per request |
| Tracing | OpenTelemetry SDK + auto-instrumentation | Env-driven OTLP exporter, off in test |
| Data migrations | [data_migrate](https://github.com/ilyakatz/data-migrate) | Schema vs data migrations tracked separately |
| IDs | [ulid](https://github.com/rafaelsales/ulid) | Time-ordered, sortable string primary keys |
| Tests | Minitest + Mocha + FactoryBot + WebMock | Parallel runner |

The full dependency list is in [Gemfile](../../Gemfile).

`bin/dev` boots web + worker via foreman, using [Procfile.dev](../../Procfile.dev).

---

## Routing layout

All API routes mount under `/v1/...`, defined in [config/routes.rb](../../config/routes.rb).

```
/v1
├── auth/...                        Player magic link + API key management
├── servers, /v1/servers/:id/...    Player surface: list servers, join, set handle, view profiles
├── worlds/:id/...                  Player surface: world map, ruins, kingdom join
├── kingdoms/:id/...                Player surface: own kingdom, build, train
├── armies/:id/...                  Player surface: dispatch, recall, split, merge, rename
└── admin
    ├── auth/...                    Admin magic link + API key management
    ├── servers, /v1/admin/servers/:id/...    Admin surface: CRUD servers, manage admins/invitations/members/worlds
    └── worlds/:id/...              Admin surface: configure, cancel, invite to world
```

Default response format is JSON (`defaults: { format: :json }` in the routes scope). Mount points are versioned (`/v1`); when the contract breaks, mount a parallel `/v2` rather than mutating `/v1` in place.

---

## The two base controllers

Every API controller inherits from one of two bases:

- [Api::BaseController](../../app/controllers/api/base_controller.rb) for player endpoints.
- [Api::Admin::BaseController](../../app/controllers/api/admin/base_controller.rb) for admin endpoints (inherits from the player one, swaps the auth filter).

Both inherit from [ApplicationController](../../app/controllers/application_controller.rb), which:

- Subclasses `ActionController::API` (no cookies, no CSRF, no view layer).
- Runs `before_action :set_current_request_id` to populate `Current.request_id`.
- Patches lograge's payload with `request_id` so the JSON log line and the response header agree.

`Api::BaseController` adds:

- `include Api::Authentication` — player Bearer auth.
- `before_action :require_player` — every action below this controller requires a valid player ApiKey.
- Three rescues: `ActiveRecord::RecordNotFound`, `ActiveRecord::RecordInvalid`, `ActionController::ParameterMissing`. Each translates to a structured error response via `render_error`.

`Api::Admin::BaseController` skips `:require_player` and runs `:require_admin` instead.

### Error envelope

`Api::BaseController#render_error` produces:

```json
{ "error": { "code": "snake_case_code", "message": "human readable", "retry_after": 30 } }
```

- `code` is a stable machine-readable token. The CLI keys off it.
- `message` is human-readable; format is unstable.
- `retry_after` appears _only_ on 429 responses (planned in Phase 11). It is mirrored in the `Retry-After` HTTP header.

Three default codes are wired today: `not_found`, `invalid`, `param_missing`. Domain services raise their own error classes; controllers translate those into envelope responses.

A deliberate detail: the `not_found` handler does not include `error.model` in the message. Leaking `ActiveRecord` internals to the API was scrubbed in commit `8335da9`.

---

## `Current` attributes

[Current](../../app/models/current.rb) is an `ActiveSupport::CurrentAttributes` thread-local container with four slots: `player`, `admin`, `api_key`, `request_id`.

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :player, :admin, :api_key, :request_id
end
```

Both auth concerns populate either `Current.player` or `Current.admin` (never both in the same request). Services that need to attribute an action to a user read `Current.player` rather than threading the player through every method signature.

Rails resets `CurrentAttributes` between requests automatically.

---

## ULID primary keys

Every model in the codebase uses 26-character base32 ULIDs as its primary key, not integers. ULIDs are time-ordered, URL-safe, and sortable, which means:

- `ORDER BY id` is approximately `ORDER BY created_at`.
- Logs and traces are readable without joining `created_at`.
- New rows from concurrent writers don't collide.

The convention is enforced two ways:

1. New AR models include the [HasUlid](../../app/models/concerns/has_ulid.rb) concern.
2. `db/schema.rb` declares every primary key column as `id: :string`.

Migrations should look like:

```ruby
create_table :widgets, id: :string do |t|
  ...
end
```

The migration from integer to ULID primary keys was done in commit `e66444f` and is now the global default. Do not introduce integer IDs.

---

## Observability

Three tools cooperate so that one request can be followed from CLI through to the DB:

1. **`X-Request-Id`** — Rails generates one if the client did not supply one. `Current.request_id` mirrors it for use inside services.
2. **lograge JSON logs** — One structured line per request, configured in [config/initializers/lograge.rb](../../config/initializers/lograge.rb). Disabled in test. `request_id` is patched into the payload by `ApplicationController#append_info_to_payload`.
3. **OpenTelemetry** — [config/initializers/opentelemetry.rb](../../config/initializers/opentelemetry.rb) wires the SDK + auto-instrumentation only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set. Service name comes from `OTEL_SERVICE_NAME` (default `dun-backend`).

Service code should emit domain events via `ActiveSupport::Notifications` under the `dun.*` namespace ([see Phase 4 tick engine](05-tick-engine.md#the-dun-event-bus)). Those events are not currently subscribed by anything in-tree, but they are the seam future integrations (Slack, webhooks, etc.) will hook into without backend changes — per `§17.3` of the GDD.

---

## Data migrations vs schema migrations

The repo uses [data_migrate](https://github.com/ilyakatz/data-migrate) to separate **what the database looks like** from **what's in it**.

- Schema migrations live in `db/migrate/`. Run with `bin/rails db:migrate`. Tracked in `db/schema.rb`.
- Data migrations live in `db/data/`. Run with `bin/rails data:migrate`. Tracked in `db/data_schema.rb`.

For backfills, prefer calling an existing service (`Buildings::Catalog::KINDS.each { ... }`) over raw SQL. Generate one with:

```bash
bin/rails generate data_migration backfill_thing
```

This separation matters at upgrade time: schema migrations must work against any data state, but data migrations may assume the schema is already up to date.

---

## Seed data

[db/seeds.rb](../../db/seeds.rb) is idempotent and bootstraps an admin from the environment:

```ruby
admin_email = ENV.fetch("DUN_BOOTSTRAP_ADMIN_EMAIL")
admin_name  = ENV.fetch("DUN_BOOTSTRAP_ADMIN_NAME")
```

`ENV.fetch` has no fallback on purpose: missing envs fail loudly. The list of required envs is in [.env.example](../../.env.example).

---

## Tests

- **Framework**: Minitest + Mocha + FactoryBot + WebMock. Parallel runner enabled.
- **Factories**, not fixtures. Factories live in [test/factories/](../../test/factories/).
- **HTTP** is locked down: `WebMock.disable_net_connect!(allow_localhost: true)` is set in `test/test_helper.rb`. Any service that calls an external HTTP API must be stubbed.
- **Controller tests** authenticate via the helper at [test/test_helpers/authentication_helpers.rb](../../test/test_helpers/authentication_helpers.rb): `authenticate_as_player(player)` and `authenticate_as_admin(admin)` both set the `Authorization: Bearer ...` header.

---

## What to do when adding a new endpoint

1. Add the route in [config/routes.rb](../../config/routes.rb), inside the right namespace.
2. Add the controller under `app/controllers/api/...` (or `api/admin/...`). Inherit from the appropriate base. Keep it thin — parse, call one service, render.
3. Put domain logic in a service under `app/services/MyNamespace/MyVerb.rb`. Conventional shape: `MyService.call(...)` returns a model or raises a nested error class.
4. Add the request/response to [docs/openapi.yaml](../openapi.yaml) in the **same commit**.
5. Write controller and service tests. The controller test exercises the auth boundary and the response envelope; the service test exercises the logic and edge cases.
6. If the feature emits a meaningful state change, emit `ActiveSupport::Notifications.instrument("dun.thing.verbed", ...)` so the future integration surface (`§17.3`) can pick it up.
