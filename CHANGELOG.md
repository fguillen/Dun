# Changelog

All notable changes to this project will be documented in this file. This project loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the version number tracks the implementation phase (`v0.10.0` ≙ Phases 1–10 of [TODO.md](TODO.md) shipped).

## [0.10.0] — 2026-05-20

First tagged release. Covers everything from the initial Rails skeleton through the Phase 10 round-end / archive system. Game loop is end-to-end playable for a single round.

### Phase 0 — Foundation

- Bootstrap Rails 8.1.3 API skeleton on Ruby 4.0.4.
- Install Solid Queue / Solid Cache / Solid Cable; add `Procfile.dev` for `bin/dev` (web + jobs via foreman).
- Mount `/v1` namespace with `Api::BaseController` and `Api::Admin::BaseController`; add health endpoint.
- Wire pagy (pagination), lograge (JSON logs), OpenTelemetry SDK + auto-instrumentation, and `X-Request-Id` propagation through `Current`.
- Idempotent `db/seeds.rb` with `ENV.fetch(...)` for bootstrap admin (no fallbacks).
- Test harness: Minitest + Mocha + FactoryBot + WebMock; parallel runner; factories under `test/factories/`; no fixtures.
- Switch every Active Record model to ULID string primary keys.
- Scrub Active Record internals from the `not_found` error envelope.

### Phase 1 — Identity, Auth, Server Membership

- Polymorphic auth substrate: `MagicLink` (15-minute, single-use, SHA-256 digest stored) and `ApiKey` (90-day rolling expiry, refreshed on each authenticated request, revocable), both `owner` on `Player` or `Admin`.
- `Player` and `Admin` models (`email`, `name`, timestamps only).
- Mailer + services for magic-link issuance and exchange.
- Player auth endpoints under `/v1/auth/...` and admin auth endpoints under `/v1/admin/auth/...`; cross-scope tokens 401.
- `Server` family migrations, models, factories, and services; magic-link consume extended to admit a player into a server on first sign-in.
- Admin and player `Server` controllers (`POST /v1/admin/servers`, `DELETE /v1/admin/servers/:id`, listing/joining for players).
- `PlayerProfile` with handle / real-name endpoints and `locked?` semantics.
- End-to-end Phase 1 integration test.

### Phase 2 — World Lifecycle & Map Generation

- `World` model with admin `propose` / `configure` / `cancel` endpoints.
- Informational `WorldInvitation` model and admin CRUD.
- Map schema: `Region`, `RegionAdjacency`, `Node`, `Ruin`.
- `Kingdom` model with bootstrap on world entry; activates `PlayerProfile#locked?`.
- Map generation pipeline:
  - Planar graph + terrain assignment.
  - `MapGeneration::PlaceNodes` with thematic terrain bias.
  - `MapGeneration::PlaceSpawns` using Poisson-disk placement.
  - `MapGeneration::PlaceRuins`.
- `Worlds::Start`, `Worlds::EndGrace`, `Worlds::Archive` services and matching jobs; late-joiner kingdom assignment.
- Player join + world/map/region/ruins read endpoints.

### Phase 3 — Resources, Buildings & Build Queue

- Per-kingdom building queue with FIFO ordering.
- Lazy stockpile accrual: resources computed on read against the last settled tick rather than every tick.
- `POST /v1/kingdoms/:kingdom_id/buildings` build orders, `GET /v1/kingdoms/:kingdom_id/buildings` listing.
- Build cost preview endpoint.

### Phase 4 — Tick Engine & Time Model

- Tick engine with `ScheduledEvent` table as the canonical scheduler.
- Internal `dun.*` event bus for cross-service notifications.
- Drives building completions, training, march arrivals, caravan arrivals, wonder progress, and round end.

### Phase 5 — Military: Units, Training, March

- `Units::Catalog` with multiplicative training-time formula.
- `Army`, `TrainingOrder`, `MarchOrder` models + JSON schemas.
- Training pipeline: `POST /v1/kingdoms/:id/train`, `DELETE` to cancel.
- `Armies::Split` / `Merge` / `Rename` with `GET` / `POST` endpoints.
- March pipeline with dispatch and recall endpoints; arrival drives next-phase resolution.
- Training cost preview endpoint.

### Phase 6 — Combat Resolution & Battle Reports

- `Battle` and `BattleParticipant` models; `wall_hp` foundation on kingdoms.
- `Combat::Round` pure per-round simulator (no Active Record).
- `Combat::Resolve`, `Combat::ComputeLoot`, `Combat::ApplyOutcome` services.
- `Marches::Arrive` wired to `Combat::Resolve` for attack intent.
- Battle read endpoints with full participant breakdowns.
- OpenAPI schemas + architecture chapter for Phase 6.

### Phase 7 — Nodes, Capture, Ruins

- Node capture/contest mechanics and resource generation routing through nodes.
- Ruin interaction model.
- Node read endpoints exposing ownership, contest state, and yield.

### Phase 8 — Trade, Caravans & Public Ledger

- Trade caravan dispatch with travel-time-based settlement.
- Public ledger of completed trades scoped to a world.

### Phase 9 — Wonder Mechanics

- Wonder construction with multi-stage progress and contribution tracking.
- Trebuchet damage interactions against wonders and walls.

### Phase 10 — Round End, Archive & Persistent Profiles

- Round-end resolution: winner determination, ledger sealing, world transition to archived state.
- Archive of world state for post-round inspection.
- Persistent stats and leaderboards across rounds for each `PlayerProfile`.

### Documentation & API contract

- OpenAPI surface: full spec at [docs/openapi.yaml](docs/openapi.yaml), originally authored as OpenAPI 3.1 and downgraded to **3.0.3** for Go codegen compatibility.
- [PRODUCT.md](PRODUCT.md) — product overview and audience.
- [docs/dun Game Design Document.v3.md](docs/dun%20Game%20Design%20Document.v3.md) — game-mechanics source of truth.
- [docs/architecture/](docs/architecture/) — per-phase backend architecture chapters with an index.
- [docs/tutorial.md](docs/tutorial.md) — end-to-end admin + player walkthrough of the API.
- Project-specific [README.md](README.md) replacing the Rails default.
- Admin force-start for proposed worlds; `GET /v1/servers/:id/worlds` player-facing world listing.

### Stack

- Ruby 4.0.4 / Rails 8.1.3 (`--api` mode), PostgreSQL 18+.
- Solid Queue / Cache / Cable.
- `pagy`, `data_migrate`, `lograge`, OpenTelemetry SDK.
- Minitest + Mocha + FactoryBot + WebMock.
- `letter_opener` for dev mail.

[0.10.0]: https://github.com/fguillen/Dun/releases/tag/v0.10.0
