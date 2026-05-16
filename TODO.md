# dun — Backend Implementation TODO

API-based Rails 8 backend for `dun`. The CLI client and any future integrations consume the JSON API exposed by this backend. Source of truth for mechanics: [docs/dun Game Design Document.v3.md](docs/dun%20Game%20Design%20Document.v3.md). Section references below (e.g. `§16.3`) point at that doc.

Per CLAUDE.md workflow: each task includes tests, ends in a commit, and uses `data_migrate` for any data backfills.

---

## Phase 0 — Bootstrap & Conventions

Foundations already partially in place (Rails 8, auth scaffold, Tailwind, factory_bot). Lock the rest before feature work.

- [x] Confirm Ruby 4.0.4 / Rails 8.1.3 / PostgreSQL 18+ versions match `§17.5`
- [x] Add Solid Queue, Solid Cache, Solid Cable to Gemfile and configure (`§17.5`)
- [x] Configure Active Job to use Solid Queue, set up `bin/jobs` worker process in `Procfile.dev`
- [x] Mount API namespace under `/v1/...` (versioned per `§17.5`)
- [x] Add `Api::BaseController` with API-key auth (Bearer header), JSON-only renders, structured error format `{error: {code, message, retry_after?}}`
- [x] Add request ID / correlation ID middleware for observability (`§17.5`)
- [x] Set up `pagy` for any paginated list endpoints (trade ledger, history, leaderboards)
- [x] Add `webmock` + `mocha` to test helper; `parallelize(workers: :number_of_processors)` (already CLAUDE.md convention)
- [x] Add `data_migrate` gem and configure (`§seeds/data` section in CLAUDE.md)
- [x] Add `lograge` (or `ougai`) for structured JSON logs (`§17.5`)
- [x] OpenTelemetry SDK + auto-instrumentation gems wired with env-driven exporter (`§17.5`)
- [x] Set up `.env.example` and `ENV.fetch(...)` boot for required secrets

---

## Phase 1 — Identity, Auth & Server Membership

Implements `§17.1` (auth, handles, real names) and `§16.7` (server-scoped identity, access rules).

Two distinct user kinds with separate auth surfaces — both use the same magic-link + 90-day Bearer `ApiKey` shape:

- **Player** — plays the game from the CLI. `/v1/auth/...` issues a player-scope ApiKey.
- **Admin** — configures servers, creates and configures worlds, invites players, manages other admins. `/v1/admin/auth/...` issues an admin-scope ApiKey. Same CLI binary as the player; admin subcommands gated by possession of an admin ApiKey.

`MagicLink` and `ApiKey` are polymorphic on `owner` (`Player` or `Admin`). A scope mismatch (player token at the admin exchange or vice versa) is rejected.

### Player models
- [x] `Player` (email, name, ...) keyed by email — uses magic link only, no password stored
- [x] `MagicLink` (token, email, expires_at, consumed_at) — 15 min expiry, single-use (`§17.1`) — polymorphic owner (Player|Admin)
- [x] `ApiKey` (player_id, token_digest, name, last_used_at, expires_at, revoked_at) — 90-day rolling — polymorphic owner (Player|Admin)
- [x] `PlayerProfile` (server_id, player_id, handle, real_name, stats jsonb, locked_during_round derived)

### Admin models
- [x] `Admin` (email, name) — same magic-link + ApiKey substrate as Player (password fields not used)
- [x] ~~`Admin` → `has_many :admin_sessions`~~ — superseded: Admin shares the polymorphic ApiKey substrate
- [x] ~~`AdminSession`~~ — superseded: no cookie sessions; admin uses Bearer ApiKey on `/v1/admin/...`

### Server models (shared)
- [x] `Server` (slug, name, owner_admin_id, max_concurrent_worlds default 2, max_worlds_per_account default 2)
- [x] `ServerAdminship` (server_id, admin_id, role, granted_by_admin_id, joined_at) — at least one admin always (`§17.1`)
- [x] `ServerAccess` (server_id, kind: domain|invite, value) — union access model (`§16.7`)
- [x] `ServerMembership` (server_id, player_id, joined_at) — player-side admission

### Auth concerns / base controllers
- [x] `Api::Authentication` concern + `Api::BaseController` requiring valid player-scope `ApiKey` Bearer token (`§17.1`)
- [x] `Api::Admin::Authentication` concern + `Api::Admin::BaseController` requiring valid admin-scope `ApiKey` Bearer token
- [x] All admin routes mount under `namespace :admin` so paths look like `/v1/admin/...`

### Player services
- [x] `MagicLinks::Request.call(email:, scope:)` — creates magic link, sends email via ActionMailer (letter_opener in dev; provider TBD per `§17.1` follow-up)
- [x] `MagicLinks::Consume.call(raw_token:, scope:)` — validates, issues `ApiKey`, runs server admission against `ServerAccess` rules + creates per-server `PlayerProfile`
- [x] `ApiKey.authenticate(raw_token, owner_type:)` — verifies, refreshes `last_used_at`, slides expiry forward; `ApiKeys::Revoke` for explicit revocation
- [x] `Players::SetHandle.call(profile, handle)` — locked-during-round guard, reserved list, format validation
- [x] `Players::SetRealName.call(profile, name)`

### Admin services
- [x] ~~`Admins::SignIn`~~ — superseded by `MagicLinks::Request`/`Consume` with `scope: "admin"`
- [x] `Admins::Invite.call(by_admin:, server:, email:)` — find-or-creates `Admin` + grants `ServerAdminship`; idempotent
- [x] `Admins::RevokeAdminship.call(by_admin:, target_admin:, server:)` — guard last-admin invariant
- [x] `Servers::Create.call(owner_admin:, name:, ...)` — initial admin = owner
- [x] `Servers::Configure.call(server, attrs)` — limits and access rules (not retroactive per `§16.7`)
- [x] `ServerInvitations::Create.call(server:, email:)` — adds an invite-kind `ServerAccess` entry; players matching it can `POST /v1/servers/:id/join`

### Player API endpoints (`/v1/...`)
- [x] `POST   /v1/auth/magic_link` → email magic link
- [x] `POST   /v1/auth/exchange` → consume link, return API key
- [x] `GET    /v1/auth/keys` / `DELETE /v1/auth/keys/:id`
- [x] `GET    /v1/servers` (list servers the player can access)
- [x] `POST   /v1/servers/:id/join` (first-time admission via domain or invite)
- [x] `GET    /v1/servers/:server_id/players/:handle` (`player show`)
- [x] `PATCH  /v1/servers/:id/me` (handle / real name)

### Admin API endpoints (`/v1/admin/...`)
- [x] `POST   /v1/admin/auth/magic_link` → email admin-scope magic link
- [x] `POST   /v1/admin/auth/exchange` → consume link, return admin ApiKey
- [x] `GET    /v1/admin/auth/keys` / `DELETE /v1/admin/auth/keys/:id`
- [x] `GET    /v1/admin/servers` (servers this admin administers)
- [x] `POST   /v1/admin/servers` (create server, creator = initial admin)
- [x] `PATCH  /v1/admin/servers/:id` (world limits; access rules via the invitations subresource)
- [x] `DELETE /v1/admin/servers/:id` (hard delete; cascades to adminships, memberships, accesses, profiles)
- [x] `GET    /v1/admin/servers/:server_id/admins` / `POST` / `DELETE /:id` (manage co-admins, last-admin guarded)
- [x] `GET    /v1/admin/servers/:server_id/invitations` / `POST` / `DELETE /:id` (invite players by email)
- [x] `GET    /v1/admin/servers/:server_id/members` (list player memberships, real names visible)

### Tests
- [x] Magic link expiry, single-use, email delivery (WebMock for any HTTP)
- [x] Domain whitelist + invite list union semantics
- [x] Handle uniqueness (case-insensitive, per-server), reserved words, format
- [x] Handle lock during active round membership (wiring tested via stub; Phase 2 activates `locked?`)
- [x] API key 90-day rolling expiry, revocation
- [x] Magic-link + ApiKey scope isolation (player vs admin) at both consume time and request time
- [x] Admin endpoints reject player-scope ApiKey; player endpoints reject admin-scope ApiKey
- [x] Last-admin invariant: cannot revoke / delete the final admin on a server
- [x] `Servers::Configure` not retroactive on existing memberships

---

## Phase 2 — World Lifecycle & Map Generation

Implements `§13` (round trigger), `§16.5` (map gen), `§16.8` (spawn), `§16.10` (terrain), `§16.11 Ruins` placement, `§16.6` (round-over reset).

### Models
- [x] `World` (server_id, name, seed, status: proposed|grace|active|archived|cancelled, t0_at, grace_closes_at, archived_at, cancelled_at, winner_kingdom_id, wonder_name)
- [x] `Region` (world_id, name, terrain, position, spawn_eligible boolean, is_hub boolean)
- [x] `RegionAdjacency` (region_a_id, region_b_id) — undirected pairs, canonical-ordered
- [x] `Node` (region_id, resource, tier, base_rate, owner_kingdom_id null, garrison jsonb, is_home_hoard)
- [x] `Ruin` (region_id, tier, garrison jsonb, cache jsonb, claimed_by_kingdom_id, claimed_at)
- [x] `Kingdom` (world_id, player_profile_id, home_region_id, stockpiles jsonb, metadata jsonb, joined_at, eliminated_at null)
- [x] `WorldInvitation` (world_id, email, invited_by_admin_id) — informational only; admission still via `ServerAccess`

### Services
- [x] `Worlds::Propose.call(server:, organizer_admin:, name:, min_players:, t0_at:, ...)` — admin-only, enforces `max_concurrent_worlds`, schedules `Worlds::StartJob` at T0
- [x] `Worlds::Configure.call(world, attrs)` — admin-only, before T0; re-enqueues StartJob if t0_at changes
- [x] `Worlds::Cancel.call(world, by_admin:)` — admin cancel (proposed → cancelled)
- [x] `Worlds::Start.call(world)` — fires when min players + t0 reached; generates map, assigns T0 kingdoms, transitions to grace
- [x] `Worlds::EndGrace.call(world)` — grace → active at T0+72h, releases unused spawn slots
- [x] `MapGeneration::Generate.call(world, players_count:)` — orchestrator chaining the steps below
  - [x] Region count: `clamp(2.5 × players + 6, 16, 64)` per `§16.5`
  - [x] Planar graph w/ avg degree 2.8–3.5 (vendored Bowyer-Watson Delaunay under `lib/dun/delaunay.rb`)
  - [x] Terrain biome clustering (Voronoi), target shares per `§16.10`
  - [x] Node placement: count `round(1.2 × players)`, distributions per `§16.5`, biased to thematic terrain per `§16.10` (70%)
  - [x] Ruin placement per `§16.11`
- [x] `MapGeneration::PlaceSpawns.call(world, players_count:, rng:)` — max-min Poisson-disk on region graph, constraints per `§16.5` + `§16.8` + `§16.10`; reserves up to `ceil(players × 1.5)` slots, relaxation chain logs warning if short
- [x] `MapGeneration::AssignLateJoiner.call(world, player_profile, hours_since_t0:)` — picks an unused reserved slot, runs `Kingdoms::Bootstrap` with the elapsed hours
- [x] `Kingdoms::Bootstrap.call(kingdom, hours_since_t0:)` — records starter buildings metadata + 500/resource base + `§16.8` stockpile bonus (capped +4000)
- [x] `Worlds::Archive.call(world)` — stub: active → archived (Phase 10 fills out the frozen-state snapshot)

### API endpoints
- [x] `GET   /v1/admin/servers/:id/worlds`
- [x] `POST  /v1/admin/servers/:id/worlds` (admin: propose/create)
- [x] `GET   /v1/admin/worlds/:id`
- [x] `PATCH /v1/admin/worlds/:id` (admin: configure before T0)
- [x] `POST  /v1/admin/worlds/:id/cancel` (admin)
- [x] `GET   /v1/admin/worlds/:id/invitations` / `POST` / `DELETE` (informational world invitations)
- [x] `POST  /v1/worlds/:id/join` (player: during proposed + grace window)
- [x] `GET   /v1/worlds/:id` (status, region count, kingdom count, your kingdom summary)
- [x] `GET   /v1/worlds/:id/map` and `GET /v1/worlds/:id/regions/:region_id` (`map`, `map <region>`)
- [x] `GET   /v1/worlds/:id/regions/:region_id/adjacent`
- [x] `GET   /v1/worlds/:id/ruins`

### Tests
- [x] Seed reproduces identical map (same seed ⇒ identical regions, terrain, nodes, ruins)
- [x] Spawn constraints enforced; relaxation order verified (degree → wilderness adjacency; terrain never relaxed)
- [x] Min 2-hop spacing between spawns
- [x] Late-joiner bonus calculation across boundaries (T0, T0+12h, T0+48h, T0+72h)
- [x] World status transitions (proposed → grace → active → archived; proposed → cancelled)

---

## Phase 3 — Resources, Buildings & Build Queue

Implements `§6`, `§7`, `§10`, `§16.4`.

### Models
- [x] `Building` (kingdom_id, kind enum [12 types], level, position) — one row per building per kingdom
- [x] `BuildOrder` (kingdom_id, building_id, target_level, started_at, completes_at, cancelled_at, completed_at)
- [x] Stockpile state lives on `Kingdom.stockpiles` jsonb (G/W/S/I + single `checkpoint_at`)

### Services / domain
- [x] `Buildings::CostFor.call(kind, level)` — `round(base × 1.75^(L-1))` per `§16.4`
- [x] `Buildings::TimeFor.call(kind, level, kingdom:)` — `min(base_time × 1.55^(L-1), 24h)` then apply Stone Mason discount (capped −30%) per `§16.4`
- [x] `Buildings::Queue.call(kingdom, kind:, target_level:)` — validates tier gates (`§10`/`§16.4`), single-slot rule (Town Hall L10/L20 unlocks more), deducts cost, idempotent retry
- [x] `Buildings::Cancel.call(build_order)` — 75% refund (floored), time lost
- [x] `Buildings::Complete.call(build_order)` — applies level bump, retroactive recalc of in-progress on Stone Mason completion, idempotent
- [x] `Buildings::ResolveCompletions.call(kingdom)` — drains ripe orders in `completes_at` order (also called proactively by Phase 4 tick)
- [x] `Stockpile::Apply.call(kingdom:, deltas:)` — atomic (row-lock), enforces Warehouse cap, raises `InsufficientResources`
- [x] `Stockpile::Read.call(kingdom)` — pure compute: `last_checkpoint + elapsed × rate`, capped at warehouse limit
- [x] `Production::RateFor.call(kingdom:, resource:)` — `base × level + node bonuses`

### Tick integration (Phase 4 owns the scheduler; building hooks live here)
- [x] Build completions resolved in `DiscreteEventTick` (Phase 3 resolves lazily on read via `Buildings::ResolveCompletions`)
- [x] Stockpile checkpoint flushed in `ProductionCheckpoint` (1 min) (Phase 3 reads lazily via `Stockpile::Read`)

### API endpoints
- [x] `GET  /v1/kingdoms/:id` (status: resources, production, queue)
- [x] `POST /v1/kingdoms/:id/build` — `{building, target_level}`
- [x] `DELETE /v1/kingdoms/:id/build/:order_id`

### Tests
- [x] Cost & time formulas at L1, L5, L10, L15, L20 against table in `§16.4`
- [x] Tier gate enforcement (Stable requires Barracks 3, etc.)
- [x] Single-slot rule; Town Hall L10/L20 unlocks more slots
- [x] Cancel refund = 75% resources, 0% time
- [x] Stone Mason retroactive recalc applies to in-progress builds (unit training / Wonder not yet shipped)
- [x] Production hard-stops at Warehouse cap (per `§16.4` open follow-up: hard stop)

---

## Phase 4 — Tick Engine & Time Model

Implements `§17.5` tick cadences. This phase wires the recurring jobs that drive every other system.

- [x] `DiscreteEventTick` (every 5s via Solid Queue recurring): processes any `ScheduledEvent` rows with `fire_at <= now` — build completions, training completions, march arrivals, battles, Wonder phase transitions, caravan arrivals, weather edges
- [x] `ProductionCheckpoint` (every 1m): flush stockpile snapshots, enforce caps
- [x] `StatsRefresh` (every 5m): leaderboard recompute eligibility, audit clusters (stub — Phases 10/11 fill in)
- [x] `WorldHousekeeping` (every 1h): grace expiry safety net, processed-event reaper (weather/rate-limit/ruin/scout cleanup added by their own phases)
- [x] `ScheduledEvent` model: `(world_id, kind, payload jsonb, fire_at, processed_at)` — single ordered source for all timed events
- [x] Idempotent event processing (use DB lock or `SELECT ... FOR UPDATE SKIP LOCKED`)
- [x] Internal event bus (`§17.3` API constraint): `ActiveSupport::Notifications` namespace `dun.*` that any future integration can subscribe to without backend rework
- [x] Tick jitter target ±5s; ETAs rounded to the minute on display

### Tests
- [x] Event scheduling, deduplication, late processing safety
- [x] Multiple events at same `fire_at` resolved deterministically (order by id)
- [x] Production checkpoint correctness across tick boundaries (drift ≤ 1m)

---

## Phase 5 — Military: Units, Training, March

Implements `§9`, `§16.3` unit stats, march mechanics, `§16.10` terrain effects on march.

### Models
- [x] `Army` (kingdom_id, name, location_region_id, status: home|marching|engaged|returning, composition jsonb)
- [x] `TrainingOrder` (kingdom_id, building_kind, unit, count, started_at, completes_at)
- [x] `MarchOrder` (army_id, origin_region_id, target_region_id, intent: attack|reinforce|scout|capture|claim_ruin|caravan, path jsonb, arrives_at, escort_units jsonb null, cargo jsonb null)

### Services
- [x] `Units::Catalog` — 8 units with stats per `§16.3` table (Atk/Def/HP/speed/capacity/cost/train time)
- [x] `Units::TrainingTimeFor.call(unit, barracks_or_stable_or_workshop_level)` — scales by building level (`base × 0.95^(L-1)`)
- [x] `Training::Queue.call(building, unit, count)` — separate queues per Barracks / Stable / Siege Workshop (`§11`)
- [x] `Armies::Split.call(army, units)` / `Armies::Rename.call(army, name)` / `Armies::Merge`
- [x] `Marches::Plan.call(origin, destination, units)` — shortest path on region graph (BFS), slowest-unit speed, terrain modifier `(mod_origin + mod_destination)/2` per `§16.10`, Knight/Scout-only armies terrain-immune
- [x] `Marches::Dispatch.call(army, target, intent)` — locks army, plans, persists `MarchOrder`, sets army marching, schedules `ScheduledEvent`
- [x] `Marches::Recall.call(march_order)` — cancels arrival, schedules retrace return (no unit losses in v1)
- [x] Carrying capacity computed from `Units::Catalog` per army (`Army#total_capacity`)

### API endpoints
- [x] `POST /v1/kingdoms/:id/train` — `{building, unit, count}`
- [x] `GET  /v1/kingdoms/:id/armies` / `GET /v1/armies/:id`
- [x] `POST /v1/armies/:id/march` — `{target_region_id, intent}`
- [x] `POST /v1/armies/:id/recall`
- [x] `POST /v1/armies/:id/split` / `POST /v1/armies/:id/rename` / `POST /v1/armies/:id/merge`

### Tests
- [x] Training time scales with building level
- [x] Separate queues per military building (Barracks, Stable, Siege concurrent)
- [x] March time across mixed terrain matches worked example in `§16.10`
- [x] Knight-only army ignores terrain penalties
- [x] Carrying capacity = sum of unit capacities

---

## Phase 6 — Combat Resolution & Battle Reports

Implements `§9`, `§16.3` combat rules.

### Models
- [x] `Battle` (world_id, region_id, attacker_kingdom_id, defender_kingdom_id, started_at, ended_at, outcome, loot jsonb, log jsonb)
- [x] `BattleParticipant` (battle_id, kingdom_id, side, starting_composition jsonb, ending_composition jsonb, casualties jsonb)

### Services
- [x] `Combat::Resolve.call(attacker_army, defender_army, region)` — 6-round sim per `§16.3`:
  1. Total Atk with RPS multipliers (Knight>Archer 1.5x, Pikeman>Knight 1.6x, Archer>Pikeman 1.4x, Catapult>Walls 3.0x via a separate wall-damage stream; Trebuchet>Wonder deferred to Phase 9)
  2. Total Def
  3. Damage = `max(0, Atk − Def × 0.5) × uniform(0.92, 1.08)`
  4. Damage distributed proportionally weighted by inverse-HP (chaff dies first)
  5. Defender bonus stacking: +20% home / +10% owned non-home / 0 elsewhere; +1%/Wall level cap +40%; terrain combat cap +25% additive (`§16.10`)
  6. Marsh attacker −10% Atk (applied before RPS) (`§16.10`)
  7. Rout: side at <15% HP routs, additional 30% flee
- [x] `Combat::ComputeLoot.call(battle)` — 25% per-resource cap or carrying capacity, whichever lower
- [x] `Combat::ApplyOutcome.call(battle)` — update stockpiles, casualties, walls level/hp, army positions (node ownership / ruin claim deferred to Phase 7)
- [x] Multi-side arrival ordering: sequential by ETA at same region — picked sequential, deterministic via existing `ScheduledEvents::Drain.order(:fire_at, :id)`
- [x] Persist round-by-round log to `battles.log` jsonb; battle report rendering serializer

### API endpoints
- [x] `GET  /v1/kingdoms/:id/battles` (recent for this kingdom)
- [x] `GET  /v1/battles/:id`
- [x] `GET  /v1/admin/worlds/:id/battles` (admin / archive)

### Tests
- [x] Pikeman counter beats Knight rush at 1.6x with reasonable counts
- [x] Defender bonus stacking math (home + Walls + terrain, capped at terrain +25%)
- [x] Variance bound, deterministic seeded RNG for tests
- [x] Rout threshold triggers
- [x] Loot capped by capacity AND by 25%-of-stockpile, lower wins
- [x] Wall destruction lowers defender bonus on follow-up attack

---

## Phase 7 — Nodes, Capture, Ruins

Implements `§7`, `§16.5` wilderness garrisons, `§16.11 Ruins` claim flow.

### Services
- [x] `Nodes::Capture.call(march_order:, node:)` — requires Catapult presence per `§9`; resolves vs garrison (one-time per `§16.5`); transfers ownership
- [x] `Nodes::Attack.call(march_order:, node:)` — contested capture from another player; fights owner's region defenders via `Combat::Resolve` (or walks in if undefended)
- [x] `Nodes::ProductionBonus.call(kingdom)` — sums flat bonuses (+120/+250/+500 per tier)
- [x] `Ruins::Claim.call(march_order:, ruin:)` — resolve vs garrison; instant grant to winner home stockpile, respect Warehouse cap (excess lost per `§16.11` via `Stockpile::Apply`); ruin row preserved with `claimed_by_kingdom_id` + `claimed_at`; emits `dun.ruin.claimed`
- [x] Home Hoard placement — already shipped in Phase 2 [`MapGeneration::PlaceSpawns#place_home_hoards`](app/services/map_generation/place_spawns.rb); Phase 7 added the §16.5 "weakest production type" assertion

### API endpoints
- [x] `GET  /v1/worlds/:id/nodes` (`node list`)
- [x] `GET  /v1/worlds/:id/nodes/:id` (`node show`)

### Tests
- [x] Catapult prerequisite for node capture (and node attack)
- [x] Garrison defeat is one-time (no respawn) — failed attempt leaves garrison intact, winning attempt clears it
- [x] Ruin cache excess lost when Warehouse cap exceeded
- [x] World announcement fired on ruin claim (`dun.ruin.claimed`)
- [x] Home Hoard matches weakest production type (diversification across spawns)

---

## Phase 8 — Trade, Caravans & Ledger

Implements `§12` (caravans, escort, interception) and `§17.2` (public ledger).

### Models
- [x] `Caravan` (world_id, sender_kingdom_id, receiver_kingdom_id, payload jsonb, escort_units jsonb, origin_region_id, destination_region_id, dispatched_at, arrives_at, delivered_at, intercepted_at, status: in_transit|delivered|intercepted, escort_army_id, outbound_march_order_id, return_march_order_id — operational FKs nullify on delete to preserve ledger history)
- [x] `TradeLedgerEntry` (world_id, caravan_id, sender_handle_at_send, receiver_handle_at_send, resource, amount, status, attacker_handle, recorded_at) — permanent for round, archived with world

### Services
- [x] `Caravans::Dispatch.call(sender_kingdom:, receiver_kingdom:, source_army:, payload:, escort_units:)` — validates capacity ≥ sum(payload), deducts stockpile, splits escort, dispatches `caravan`-intent march, writes in_transit ledger rows
- [x] `Caravans::Arrive.call(caravan:)` — routes between Deliver and Intercept based on third-party hostile presence at destination (status: home/engaged); strongest by raw atk, ties by army.id
- [x] `Caravans::Intercept.call(caravan:, attacker_army:)` — combat between escort (attacker) and hostile (defender) via `Combat::Resolve(defender_army:)` + `Combat::ApplyEscortOutcome`; on escort loss, payload → attacker home stockpile (capped by surviving capacity, then warehouse); escort win falls through to Deliver
- [x] `Caravans::Deliver.call(caravan)` — payload → receiver stockpile (Warehouse capped, excess silently dropped per `§16.11`), schedules `caravan_return` retrace march
- [x] `Caravans::CompleteReturn.call(caravan:)` — merges escort survivors into sender's home army at origin (or converts the escort in place if no host exists)
- [x] `TradeLedger::Record.call(caravan:, status:, attacker_handle:)` — one row per non-zero resource on dispatch; status mutated in place on Deliver/Intercept
- [x] `Combat::Resolve` extended to accept `defender_army:` override (bypass region-home-kingdom defender lookup + walls/home bonus); routes to `Combat::ApplyEscortOutcome` instead of `ApplyOutcome` (no loot transfer; cargo handled by Intercept)

### API endpoints
- [x] `POST /v1/kingdoms/:id/caravans` — `send <player> <amount> <resource>`
- [x] `GET  /v1/worlds/:id/trade-ledger` — pagy-paginated, optional `player`, `since`, `limit`, `page` filters

### Tests
- [x] Escort capacity gates payload size
- [x] Interception attribution: both sender and interceptor handles visible on ledger; deterministic strongest-hostile pick
- [x] Warehouse cap respected on delivery (excess silently lost, consistent with Ruin claim)
- [x] Ledger handles snapshotted at dispatch (immune to later handle renames), world-scoped
- [x] Full lifecycle integration test: dispatch → DiscreteEventTick → deliver (or intercept) → return march merges escort

---

## Phase 9 — Wonder Mechanics

Implements `§14` and `§16.2`. Round-end critical path.

### Models
- [x] `Wonder` (kingdom_id, name, status: foundation|construction|consecration|completed|destroyed, hp, target_hp, started_at, construction_started_at, consecration_at, completed_at, destroyed_at, paused_until, last_construction_at, pending_milestone_percent, milestones_paid jsonb, repaired_hp_by_phase jsonb) — partial unique index on `kingdom_id` for live statuses
- [x] `WonderDamageEvent` (wonder_id, attacker_kingdom_id, battle_id, trebuchets_surviving, hp_before, hp_after, occurred_at)

### Services
- [x] `Wonders::Prerequisites.call(kingdom:)` — world active, building gates (town_hall 10, quarry 10, siege_workshop 5), ≥3 controlled nodes, affordable; raises `NotMet(reason:)` (`§14`/`§16.2`)
- [x] `Wonders::Start.call(kingdom:, name:)` — deduct 25% upfront, status goes straight to `construction` per §14 ("Foundation is instant"), schedules +90h transition, emits `dun.wonder.started`, HP=1000
- [x] `Wonders::ApplyConstruction` (lazy, no per-tick writer) — accrues 100 HP/h from `last_construction_at`, clamps at milestones, respects `paused_until`
- [x] `Wonders::PayMilestone.call(wonder:, percent:)` — explicit pay (player calls after auto-pause at 25/50/75%); deducts 10%, clears pending, resumes from `now`
- [x] `Wonders::Damage.call(wonder:, attacker_kingdom:, trebuchets_surviving:, battle:)` — `-50 HP × trebuchets`; records `WonderDamageEvent`; if HP→0 → `Wonders::Destroy.call` (resources lost, queue unlocked, builder may restart)
- [x] `Wonders::Repair.call(wonder:, hp:)` — 1 HP per 8 Stone, cap 2000 HP per phase (independent), pause construction 30 min per 500 HP repaired (stacks)
- [x] `Wonders::EnterConsecration.call(wonder:)` — scheduled handler at +90h: pay 5%, schedule complete at +24h, emit `dun.wonder.entered_consecration`; re-schedules if not ready
- [x] `Wonders::Complete.call(wonder:)` — if Consecration ends with HP>0 → minimal world archive (winner_kingdom_id, wonder_name, status: archived); full freeze deferred to Phase 10
- [x] `Wonders::Destroy.call(wonder:)` — flips status, cancels pending `wonder_phase` events, emits `dun.wonder.destroyed`
- [x] `Wonders::Cancel.call(wonder:)` — voluntary abandonment (same effect as destruction)
- [x] `Wonders::LiveFor.call(kingdom)` — used by `Buildings::Queue` lock and combat damage hook
- [ ] No new weather windows scheduled once Consecration begins — deferred to Phase 12 (`§16.11`)

### API endpoints
- [x] `GET    /v1/kingdoms/:id/wonder` (status, HP, milestone, paused_until, etc.)
- [x] `POST   /v1/kingdoms/:id/wonder` — `{name}` (start)
- [x] `POST   /v1/kingdoms/:id/wonder/repair` — `{hp}`
- [x] `POST   /v1/kingdoms/:id/wonder/milestone` — `{percent}`
- [x] `DELETE /v1/kingdoms/:id/wonder` (cancel; status→destroyed)
- [x] `GET    /v1/worlds/:id/wonders` (public list)

### Tests
- [x] Foundation payment exact: 25% per `§16.2` table
- [x] Milestone payments freeze construction when missed
- [x] Trebuchet damage = 50 × surviving units
- [x] Repair cap 2000 HP per phase enforced independently per phase
- [x] Consecration timer scheduled correctly, world announcement fired
- [x] Destruction restart loses all paid resources
- [x] Build queue locked during construction; unit training continues
- [ ] No weather windows spawn during Consecration — deferred to Phase 12

---

## Phase 10 — Round End, Archive & Persistent Profiles

Implements `§16.6` (round freeze, archive) and `§17.4` (stats, leaderboards, titles, deletion).

### Models
- [ ] `RoundArchive` (world_id, frozen_state jsonb or per-table snapshots, winner, wonder_name, ended_at)
- [ ] `PlayerProfileStats` (already on `PlayerProfile` jsonb or split out): `rounds_played`, `rounds_won`, `wonders_completed`, `wonders_destroyed`, `peak_nodes`, `raids_launched`, `raids_defended`, `raids_won_offense`, `raids_won_defense`, `resources_looted`
- [ ] `PlayerTitle` (player_profile_id, world_id, title, awarded_at, count)
- [ ] `LeaderboardSnapshot` (server_id, kind: champions|wreckers|warlords|veterans, snapshot_at, entries jsonb)

### Services
- [ ] `Rounds::End.call(world, winning_kingdom)` — instant freeze (halt marches, freeze queues), set world status to archived, fire announcement
- [ ] `Profiles::Increment.call(player, deltas)` — atomic stat updates at resolution moments
- [ ] `Wreckers::Attribute.call(wonder_destroyed_event)` — killing-blow attribution per `§17.4`, ties broken by largest Trebuchet contribution then earliest dispatch
- [ ] `Titles::Award.call(player, world_name)` — `[Champion of <World> ×N]`
- [ ] `Leaderboards::Recompute.call(server)` — runs only on round end, snapshots cached
- [ ] `Accounts::Delete.call(user)` — per `§17.4`: anonymize handle → `[deleted player]` across all archives, purge real name immediately, free handle after 30 days, irreversible

### API endpoints
- [ ] `GET  /v1/servers/:id/hall-of-fame` (and `:leaderboard` / `--all` variants)
- [ ] `GET  /v1/worlds/:id/archive`
- [ ] `DELETE /v1/auth/account`

### Tests
- [ ] Round-end freeze halts in-flight marches, build queues
- [ ] Killing-blow attribution and tiebreakers
- [ ] Title count suffix display for repeat wins on same world
- [ ] Per-server scoping — same email on two servers ⇒ independent profiles
- [ ] Account deletion: real_name purged immediately, handle anonymized in archives, 30-day reservation

---

## Phase 11 — Anti-Abuse: Reports, Rate Limits, Raid Cap

Implements `§17.2`.

### Models
- [ ] `Report` (server_id, reporter_id, target_id, reason, status: open|dismissed|warned|suspended|removed, admin_action_log jsonb)
- [ ] `RateLimitWindow` (user_id, kind: minute|hour, count, window_start)
- [ ] `AuditCluster` (server_id, signature, member_user_ids jsonb, surfaced_at) — IP/device fingerprint clusters

### Services
- [ ] `RateLimits::Check.call(user, command_kind)` — 60 writes/min, 1000/hr per account, reads unlimited; structured error with `retry_after`; per-server admin override
- [ ] `Raids::CapCheck.call(attacker, target_player, world)` — 3 per attacker-target pair per 24h sliding, Wonder assaults exempt, counts successful arrivals not dispatches; per-server config
- [ ] `Reports::File.call(reporter, target, reason)` — non-anonymous
- [ ] `Reports::Act.call(report, admin, action)` — dismiss/warn/suspend/remove; logged; visible to reporter and target after action
- [ ] `AuditClusters::Recompute` (5-min tick) — surface IP / device clusters for admin review (no auto-action)

### API endpoints
- [ ] `POST  /v1/servers/:id/reports` (player files report)
- [ ] `GET   /v1/admin/servers/:id/reports` (admin queue)
- [ ] `PATCH /v1/admin/servers/:id/reports/:id` (admin action: dismiss/warn/suspend/remove)
- [ ] `GET   /v1/admin/servers/:id/audit` (admin: IP/device clusters, no auto-action)
- [ ] `PATCH /v1/admin/servers/:id/rate_limits` (admin override of write limits per `§17.2`)

### Tests
- [ ] 60/min limit enforced, retry_after correct
- [ ] Raid cap counts arrivals only, exempts Wonder assaults
- [ ] Configurable cap per server (0 = unlimited)
- [ ] Reports non-anonymous, server-scoped
- [ ] Audit cluster surfacing without auto-action

---

## Phase 12 — Weather Windows

Implements `§16.11`.

- [ ] `WeatherWindow` (world_id, terrain, modifier: storms|fair_weather|fog, announces_at, opens_at, closes_at)
- [ ] `WeatherScheduler` — first window T0+96h, then every 72–96h seeded; halts spawning new windows when any Wonder enters Consecration; active windows finish on schedule
- [ ] `Weather::EffectFor.call(region, at_time)` — additive with terrain base; combat respects +25% terrain cap; march no cap; Knights/Scouts immune; Fair Weather capped at 1.0x (no inversion)
- [ ] World announcements at telegraph (−12h), open, close
- [ ] `GET /v1/worlds/:id/weather`
- [ ] Tests: cadence reproducible, stacking math, Consecration freeze on spawn

---

## Phase 13 — Fog of War & Scouting (v1.1 — designed in `§16.9`)

Designed but not shipped in v1. Build the schema and command surface now if it helps validate Phases 5/6; otherwise defer.

- [ ] `ScoutMission` (kingdom_id, target_region_id, scout_count, dispatched_at, arrives_at, returns_at, status, report jsonb)
- [ ] `WatchtowerIntel` — read-time projection from Watchtower level per `§16.9` table
- [ ] Size buckets for incoming attacks (Small/Medium/Large/Massive)
- [ ] Scout interception detection (10+ Scouts OR 20+ Archers OR Watchtower ≥5; 50% slip for sub-10 stacks)
- [ ] Anonymous attribution on detection
- [ ] `POST /v1/kingdoms/:id/scout`, `GET /v1/kingdoms/:id/scout-reports`
- [ ] Wonder fully public regardless of fog
- [ ] Defer Phase 13 unless prioritized.

---

## Phase 14 — Observability, Deployment & Ops

Implements `§17.5` runtime/ops surface.

- [ ] OpenTelemetry exporters configurable via env (Tempo/Loki/VictoriaMetrics defaults documented)
- [ ] `docker-compose.yml` services: `dun-web`, `dun-worker`, `postgres`, `caddy`
- [ ] `docker-compose --profile observability` adds Grafana, Tempo, Loki, VictoriaMetrics
- [ ] `bin/dun init-server` task: generate secrets, run migrations + data migrations, bootstrap initial admin
- [ ] `bin/dun upgrade` task: pre-migration `pg_dump` backup, run migrations behind health check, restart
- [ ] Backup job: nightly `pg_dump` to configurable destination (S3-compatible / local volume)
- [ ] Multi-arch Docker images (amd64 + arm64) via GitHub Actions
- [ ] Caddy automatic Let's Encrypt; documented manual cert mode for air-gapped
- [ ] Runbook in `docs/runbook.md` (only if requested per CLAUDE.md "no docs unless asked")

---

## Cross-cutting checks before each release

- [ ] `rails test` passes (parallel runner)
- [ ] Schema and data migrations both run cleanly on a fresh DB and an upgraded DB
- [ ] All write endpoints rate-limited and authorized
- [ ] API responses available as JSON with stable shape (consumed by CLI per `§16.1`)
- [ ] Internal `dun.*` events emitted on every state-change moment so future integrations (`§17.3`) need no backend change
- [ ] Seed data idempotent (`db/seeds.rb`), admin bootstrap via `ENV.fetch`
- [ ] Per-task git commit at end of work

---

## Out of v1 scope (recorded so design surface doesn't absorb them)

- Slack / email / calendar / webhook / push integrations (`§17.3`)
- SSO beyond magic link (`§17.1` v1.1)
- Marketplace order-book trading (`§12`)
- Specialized units, Heroes, Quests, additional cosmetics (`§19`)
- Managed hosting / SaaS surface (`§17.5`, `§18.1`)
- Multi-tenant infra (single-tenant per server is the v1 commitment)
