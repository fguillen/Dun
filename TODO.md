# dun — Backend Implementation TODO

API-based Rails 8 backend for `dun`. The CLI client and any future integrations consume the JSON API exposed by this backend. Source of truth for mechanics: [docs/dun Game Design Document.v3.md](docs/dun%20Game%20Design%20Document.v3.md). Section references below (e.g. `§16.3`) point at that doc.

Per CLAUDE.md workflow: each task includes tests, ends in a commit, and uses `data_migrate` for any data backfills.

---

## Phase 0 — Bootstrap & Conventions

Foundations already partially in place (Rails 8, auth scaffold, Tailwind, factory_bot). Lock the rest before feature work.

- [ ] Confirm Ruby 4.0.4 / Rails 8.1.3 / PostgreSQL 18+ versions match `§17.5`
- [ ] Add Solid Queue, Solid Cache, Solid Cable to Gemfile and configure (`§17.5`)
- [ ] Configure Active Job to use Solid Queue, set up `bin/jobs` worker process in `Procfile.dev`
- [ ] Mount API namespace under `/v1/...` (versioned per `§17.5`)
- [ ] Add `Api::BaseController` with API-key auth (Bearer header), JSON-only renders, structured error format `{error: {code, message, retry_after?}}`
- [ ] Add request ID / correlation ID middleware for observability (`§17.5`)
- [ ] Set up `pagy` for any paginated list endpoints (trade ledger, history, leaderboards)
- [ ] Add `webmock` + `mocha` to test helper; `parallelize(workers: :number_of_processors)` (already CLAUDE.md convention)
- [ ] Add `data_migrate` gem and configure (`§seeds/data` section in CLAUDE.md)
- [ ] Add `lograge` (or `ougai`) for structured JSON logs (`§17.5`)
- [ ] OpenTelemetry SDK + auto-instrumentation gems wired with env-driven exporter (`§17.5`)
- [ ] Set up `.env.example` and `ENV.fetch(...)` boot for required secrets

---

## Phase 1 — Identity, Auth & Server Membership

Implements `§17.1` (auth, handles, real names) and `§16.7` (server-scoped identity, access rules).

Two distinct user kinds with separate auth:

- **Player** — plays the game from the CLI. Magic-link sign-in, long-lived `ApiKey` bearer tokens. Lives entirely under `/v1/...` (non-admin).
- **Admin** — configures servers, creates and configures worlds, invites players, manages other admins. Password-based with session cookies (Rails 8 auth generator shape). All admin endpoints scoped under `/v1/admin/...`.

### Player models
- [ ] `Player` (email, name, ...) keyed by email — uses magic link only, no password stored
- [ ] `MagicLink` (token, email, expires_at, consumed_at) — 15 min expiry, single-use (`§17.1`)
- [ ] `ApiKey` (player_id, token_digest, name, last_used_at, expires_at, revoked_at) — 90-day rolling
- [ ] `PlayerProfile` (server_id, player_id, handle, real_name, stats jsonb, locked_during_round derived)

### Admin models (separate auth)
- [ ] `Admin` (email, password_digest, name, ...) — Rails 8 auth generator
- [ ] `Admin` → `has_many :admin_sessions`
- [ ] `AdminSession` (admin_id, user_agent, ip_address, ...) — cookie-based session per Rails 8 auth generator

### Server models (shared)
- [ ] `Server` (slug, name, owner_admin_id, max_concurrent_worlds default 2, max_worlds_per_account default 2)
- [ ] `ServerAdminship` (server_id, admin_id, role, granted_by_admin_id, joined_at) — at least one admin always (`§17.1`)
- [ ] `ServerAccess` (server_id, kind: domain|invite, value) — union access model (`§16.7`)
- [ ] `ServerMembership` (server_id, player_id, joined_at) — player-side admission

### Auth concerns / base controllers
- [ ] `Authentication` concern + `Api::BaseController` requiring valid `ApiKey` Bearer token (`§17.1`)
- [ ] `Admin::Authentication` concern + `Api::Admin::BaseController` requiring admin session, enforces admin role (per CLAUDE.md namespace-scoped base controller pattern)
- [ ] All admin routes mount under `namespace :admin` so paths look like `/v1/admin/...`

### Player services
- [ ] `MagicLinks::Request.call(email)` — creates magic link, sends email via ActionMailer (provider TBD per `§17.1` follow-up; start with letter_opener in dev)
- [ ] `MagicLinks::Consume.call(token)` — validates, issues `ApiKey`, runs server admission against `ServerAccess` rules
- [ ] `ApiKeys::Authenticate.call(token)` — verifies, refreshes `last_used_at`, expires when stale
- [ ] `Players::SetHandle.call(profile, handle)` — between-rounds-only, reserved list, format validation
- [ ] `Players::SetRealName.call(profile, name)`

### Admin services
- [ ] `Admins::SignIn.call(email, password)` — issues `AdminSession`
- [ ] `Admins::Invite.call(by_admin:, email:)` — creates another `Admin` and grants `ServerAdminship`; cannot drop below one admin
- [ ] `Admins::RevokeAdminship.call(by_admin:, target_admin:, server:)` — guard last-admin invariant
- [ ] `Servers::Create.call(owner_admin:, name:, ...)` — initial admin = owner
- [ ] `Servers::Configure.call(server, attrs)` — limits and access rules (not retroactive per `§16.7`)
- [ ] `ServerInvitations::Create.call(server, email)` — adds an invite-kind `ServerAccess` entry; players matching it can `POST /v1/servers/:id/join`

### Player API endpoints (`/v1/...`)
- [ ] `POST   /v1/auth/magic_link` → email magic link
- [ ] `POST   /v1/auth/exchange` → consume link, return API key
- [ ] `GET    /v1/auth/keys` / `DELETE /v1/auth/keys/:id`
- [ ] `GET    /v1/servers` (list servers the player can access)
- [ ] `POST   /v1/servers/:id/join` (first-time admission via domain or invite)
- [ ] `GET    /v1/servers/:id/players/:handle` (`player show`)
- [ ] `PATCH  /v1/servers/:id/me` (handle / real name)

### Admin API endpoints (`/v1/admin/...`)
- [ ] `POST   /v1/admin/auth/sign_in` (password) → session cookie
- [ ] `DELETE /v1/admin/auth/sign_out`
- [ ] `POST   /v1/admin/auth/password_reset` (request) and consume
- [ ] `GET    /v1/admin/servers` (servers this admin administers)
- [ ] `POST   /v1/admin/servers` (create server, creator = initial admin)
- [ ] `PATCH  /v1/admin/servers/:id` (access rules, world limits)
- [ ] `GET    /v1/admin/servers/:id/admins` / `POST` / `DELETE /:admin_id` (manage co-admins, last-admin guarded)
- [ ] `GET    /v1/admin/servers/:id/invitations` / `POST` / `DELETE /:id` (invite players by email)
- [ ] `GET    /v1/admin/servers/:id/members` (list player memberships, real names visible)

### Tests
- [ ] Magic link expiry, single-use, email delivery (WebMock for any HTTP)
- [ ] Domain whitelist + invite list union semantics
- [ ] Handle uniqueness (case-insensitive, per-server), reserved words, format
- [ ] Handle lock during active round membership
- [ ] API key 90-day rolling expiry, revocation
- [ ] Admin sign-in / sign-out; admin session scoped via cookies
- [ ] Admin endpoints reject API-key (player) auth; player endpoints reject admin-session auth
- [ ] Last-admin invariant: cannot revoke / delete the final admin on a server
- [ ] `Servers::Configure` not retroactive on existing memberships

---

## Phase 2 — World Lifecycle & Map Generation

Implements `§13` (round trigger), `§16.5` (map gen), `§16.8` (spawn), `§16.10` (terrain), `§16.11 Ruins` placement, `§16.6` (round-over reset).

### Models
- [ ] `World` (server_id, name, seed, status: proposed|grace|active|archived, t0_at, grace_closes_at, ended_at, winner_player_id, wonder_name)
- [ ] `Region` (world_id, name, terrain, position, spawn_eligible boolean, is_hub boolean)
- [ ] `RegionAdjacency` (region_a_id, region_b_id) — undirected pairs
- [ ] `Node` (region_id, resource, tier, base_rate, owner_kingdom_id null, garrison jsonb)
- [ ] `Ruin` (region_id, tier, garrison jsonb, cache jsonb, claimed_by_kingdom_id, claimed_at)
- [ ] `Kingdom` (world_id, player_profile_id, home_region_id, stockpiles jsonb, joined_at, eliminated_at null)
- [ ] `WorldInvitation` (world_id, email, status)

### Services
- [ ] `Worlds::Propose.call(server:, organizer_admin:, min_players:, scheduled_t0:)` — admin-only (per Phase 1)
- [ ] `Worlds::Configure.call(world, attrs)` — admin-only, before T0
- [ ] `Worlds::Start.call(world)` — fires when min players + t0 reached; generates map
- [ ] `MapGeneration::Generate.call(world, seed:, players:)`:
  - Region count: `clamp(2.5 × players + 6, 16, 64)` per `§16.5`
  - Planar graph w/ avg degree 2.8–3.5
  - Terrain biome clustering, target shares per `§16.10`
  - Node placement: count `1.2 × players`, distributions per `§16.5`, biased to thematic terrain per `§16.10` (70% pref)
  - Ruin placement per `§16.11`
- [ ] `MapGeneration::PlaceSpawns.call(world)` — Poisson-disk on region graph, constraints per `§16.5` + `§16.8` + `§16.10` (Plains/Hills only); reserve `ceil(players × 1.5)` slots
- [ ] `MapGeneration::AssignLateJoiner.call(world, player)` — random reserved slot, `+1000/12h` stockpile bonus capped `+4000` per `§16.8`
- [ ] `Kingdoms::Bootstrap.call(kingdom)` — starter buildings (4 resource @L1, Barracks L1, Walls L1, Watchtower L1), 500/resource, 20 Levy (`§13`)
- [ ] `Worlds::Archive.call(world)` — freeze state when winner declared

### API endpoints
- [ ] `POST  /v1/admin/servers/:id/worlds` (admin: propose/create)
- [ ] `PATCH /v1/admin/worlds/:id` (admin: configure before T0)
- [ ] `POST  /v1/admin/worlds/:id/cancel` (admin)
- [ ] `POST  /v1/worlds/:id/join` (player: during proposed + grace window)
- [ ] `GET   /v1/worlds/:id` (status, region count, kingdoms)
- [ ] `GET   /v1/worlds/:id/map` and `GET /v1/worlds/:id/map/:region` (`map`, `map <region>`)
- [ ] `GET   /v1/worlds/:id/regions/:id/adjacent`
- [ ] `GET   /v1/worlds/:id/ruins`

### Tests
- [ ] Seed reproduces identical map (same seed ⇒ identical regions, terrain, nodes, ruins)
- [ ] Spawn constraints enforced; relaxation order verified (degree → wilderness adjacency; terrain never relaxed)
- [ ] Min 2-hop spacing between kingdoms
- [ ] Late-joiner bonus calculation across boundaries (T0, T0+12h, T0+48h, T0+72h)
- [ ] World status transitions

---

## Phase 3 — Resources, Buildings & Build Queue

Implements `§6`, `§7`, `§10`, `§16.4`.

### Models
- [ ] `Building` (kingdom_id, kind enum [12 types], level, position) — one row per building per kingdom
- [ ] `BuildOrder` (kingdom_id, building_id, target_level, started_at, completes_at, cancelled_at)
- [ ] Stockpile state lives on `Kingdom.stockpiles` jsonb (G/W/S/I + per-resource last_checkpoint_at)

### Services / domain
- [ ] `Buildings::CostFor.call(kind, level)` — `base × 1.75^(L-1)` per `§16.4`
- [ ] `Buildings::TimeFor.call(kind, level, kingdom:)` — `min(base_time × 1.55^(L-1), 24h)` then apply Stone Mason discount (capped −30%) per `§16.4`
- [ ] `Buildings::Queue.call(kingdom, building, ...)` — validates tier gates (`§10`/`§16.4`), single-slot rule (Town Hall L10/L20 unlocks more), deducts cost
- [ ] `Buildings::Cancel.call(build_order)` — 75% refund, time lost
- [ ] `Buildings::Complete.call(build_order)` — applies level bump, retroactive recalc of in-progress on Stone Mason completion
- [ ] `Stockpile::Apply.call(kingdom, deltas)` — atomic, enforces Warehouse cap
- [ ] `Stockpile::Read.call(kingdom)` — lazy materialization: `last_checkpoint + elapsed × rate`, capped at warehouse limit
- [ ] `Production::RateFor.call(kingdom, resource)` — sum of `base × level` + node bonuses

### Tick integration (Phase 4 owns the scheduler; building hooks live here)
- [ ] Build completions resolved in `DiscreteEventTick`
- [ ] Stockpile checkpoint flushed in `ProductionCheckpoint` (1 min)

### API endpoints
- [ ] `GET  /v1/kingdoms/:id` (status: resources, production, queue)
- [ ] `POST /v1/kingdoms/:id/build` — `{building, target_level}`
- [ ] `DELETE /v1/kingdoms/:id/build/:order_id`

### Tests
- [ ] Cost & time formulas at L1, L5, L10, L15, L20 against table in `§16.4`
- [ ] Tier gate enforcement (Stable requires Barracks 3, etc.)
- [ ] Single-slot rule; Town Hall L10 unlocks +1 slot
- [ ] Cancel refund = 75% resources, 0% time
- [ ] Stone Mason retroactive recalc applies to in-progress builds, not unit training, not Wonder
- [ ] Production hard-stops at Warehouse cap (per `§16.4` open follow-up: hard stop)

---

## Phase 4 — Tick Engine & Time Model

Implements `§17.5` tick cadences. This phase wires the recurring jobs that drive every other system.

- [ ] `DiscreteEventTick` (every 5s via Solid Queue recurring): processes any `ScheduledEvent` rows with `fire_at <= now` — build completions, training completions, march arrivals, battles, Wonder phase transitions, caravan arrivals, weather edges
- [ ] `ProductionCheckpoint` (every 1m): flush stockpile snapshots, enforce caps
- [ ] `StatsRefresh` (every 5m): leaderboard recompute eligibility, audit clusters
- [ ] `WorldHousekeeping` (every 1h): grace expiry, weather scheduling lookahead, rate-limit windows, ruin/scout cleanup
- [ ] `ScheduledEvent` model: `(world_id, kind, payload jsonb, fire_at, processed_at)` — single ordered source for all timed events
- [ ] Idempotent event processing (use DB lock or `SELECT ... FOR UPDATE SKIP LOCKED`)
- [ ] Internal event bus (`§17.3` API constraint): `DomainEvent` table or `ActiveSupport::Notifications` namespace `dun.*` that any future integration can subscribe to without backend rework
- [ ] Tick jitter target ±5s; ETAs rounded to the minute on display

### Tests
- [ ] Event scheduling, deduplication, late processing safety
- [ ] Multiple events at same `fire_at` resolved deterministically (order by id)
- [ ] Production checkpoint correctness across tick boundaries (drift ≤ 1m)

---

## Phase 5 — Military: Units, Training, March

Implements `§9`, `§16.3` unit stats, march mechanics, `§16.10` terrain effects on march.

### Models
- [ ] `Army` (kingdom_id, name, location_region_id, status: home|marching|engaged|returning, composition jsonb)
- [ ] `TrainingOrder` (kingdom_id, building_kind, unit, count, started_at, completes_at)
- [ ] `MarchOrder` (army_id, origin_region_id, target_region_id, intent: attack|reinforce|scout|capture|claim_ruin|caravan, path jsonb, arrives_at, escort_units jsonb null, cargo jsonb null)

### Services
- [ ] `Units::Catalog` — 8 units with stats per `§16.3` table (Atk/Def/HP/speed/capacity/cost/train time)
- [ ] `Units::TrainingTimeFor.call(unit, barracks_or_stable_or_workshop_level)` — scales by building level
- [ ] `Training::Queue.call(building, unit, count)` — separate queues per Barracks / Stable / Siege Workshop (`§11`)
- [ ] `Armies::Split.call(army, units)` / `Armies::Rename.call(army, name)` / `Armies::Merge`
- [ ] `Marches::Plan.call(origin, destination, units)` — shortest path on region graph, slowest-unit speed, terrain modifier `(mod_origin + mod_destination)/2` per `§16.10`, Knights/Scouts terrain-immune
- [ ] `Marches::Dispatch.call(army, target, intent)` — deducts units from home garrison, creates `MarchOrder` and `ScheduledEvent`
- [ ] `Marches::Recall.call(march_order)` — schedule return; decide whether to cost unit losses (open follow-up `§16.3`)
- [ ] Carrying capacity computed from `Units::Catalog` per army

### API endpoints
- [ ] `POST /v1/kingdoms/:id/train` — `{building, unit, count}`
- [ ] `GET  /v1/kingdoms/:id/armies` / `GET /v1/armies/:id`
- [ ] `POST /v1/armies/:id/march` — `{target, intent}`
- [ ] `POST /v1/armies/:id/recall`
- [ ] `POST /v1/armies/:id/split` / `POST /v1/armies/:id/rename`

### Tests
- [ ] Training time scales with building level
- [ ] Separate queues per military building (Barracks, Stable, Siege concurrent)
- [ ] March time across mixed terrain matches worked example in `§16.10`
- [ ] Knight-only army ignores terrain penalties
- [ ] Carrying capacity = sum of unit capacities

---

## Phase 6 — Combat Resolution & Battle Reports

Implements `§9`, `§16.3` combat rules.

### Models
- [ ] `Battle` (world_id, region_id, attacker_kingdom_id, defender_kingdom_id, started_at, ended_at, outcome, loot jsonb, log jsonb)
- [ ] `BattleParticipant` (battle_id, kingdom_id, side, starting_composition jsonb, ending_composition jsonb, casualties jsonb)

### Services
- [ ] `Combat::Resolve.call(attacker_army, defender_army, region)` — 6-round sim per `§16.3`:
  1. Total Atk with RPS multipliers (Knight>Archer 1.5x, Pikeman>Knight 1.6x, Archer>Pikeman 1.4x, Catapult>Walls 3.0x, Trebuchet>Wonder 50 HP/unit)
  2. Total Def
  3. Damage = `max(0, Atk − Def × 0.5) × uniform(0.92, 1.08)`
  4. Damage distributed proportionally weighted by inverse-HP (chaff dies first)
  5. Defender bonus stacking: +20% home / +10% owned non-home / 0 elsewhere; +1%/Wall level cap +40%; terrain combat cap +25% additive (`§16.10`)
  6. Marsh attacker −10% Atk (applied before RPS) (`§16.10`)
  7. Rout: side at <15% HP routs, additional 30% flee
- [ ] `Combat::ComputeLoot.call(battle)` — 25% per-resource cap or carrying capacity, whichever lower
- [ ] `Combat::ApplyOutcome.call(battle)` — update stockpiles, casualties, node ownership for capture intent, ruin claim, etc.
- [ ] Multi-side arrival ordering: sequential by ETA at same region (`§16.3` open follow-up — pick sequential)
- [ ] Persist round-by-round log to `battles.log` jsonb; battle report rendering serializer

### API endpoints
- [ ] `GET  /v1/kingdoms/:id/battles` (recent for this kingdom)
- [ ] `GET  /v1/battles/:id`
- [ ] `GET  /v1/worlds/:id/battles` (admin / archive)

### Tests
- [ ] Pikeman counter beats Knight rush at 1.6x with reasonable counts
- [ ] Defender bonus stacking math (home + Walls + terrain, capped at terrain +25%)
- [ ] Variance bound, deterministic seeded RNG for tests
- [ ] Rout threshold triggers
- [ ] Loot capped by capacity AND by 25%-of-stockpile, lower wins
- [ ] Wall destruction lowers defender bonus on follow-up attack

---

## Phase 7 — Nodes, Capture, Ruins

Implements `§7`, `§16.5` wilderness garrisons, `§16.11 Ruins` claim flow.

### Services
- [ ] `Nodes::Capture.call(army, node)` — requires Catapult presence per `§9`; resolves vs garrison (one-time per `§16.5`); transfers ownership
- [ ] `Nodes::Attack.call(army, node)` — contested capture from another player; resolves vs garrison
- [ ] `Nodes::ProductionBonus.call(kingdom)` — sums flat bonuses (+120/+250/+500 per tier)
- [ ] `Ruins::Claim.call(army, ruin)` — resolve vs garrison; instant grant to winner home stockpile, respect Warehouse cap (excess lost per `§16.11`); consume ruin; fire announcement
- [ ] Home Hoard placement: every kingdom gets one Standard-tier node matched to weakest production type at spawn (`§16.5`)

### API endpoints
- [ ] `GET  /v1/worlds/:id/nodes` (`node list`)
- [ ] `GET  /v1/nodes/:id` (`node show`)

### Tests
- [ ] Catapult prerequisite for node capture
- [ ] Garrison defeat is one-time (no respawn)
- [ ] Ruin cache excess lost when Warehouse cap exceeded
- [ ] World announcement fired on ruin claim
- [ ] Home Hoard matches weakest production type

---

## Phase 8 — Trade, Caravans & Ledger

Implements `§12` (caravans, escort, interception) and `§17.2` (public ledger).

### Models
- [ ] `Caravan` (world_id, sender_kingdom_id, receiver_kingdom_id, payload jsonb, escort_units jsonb, origin_region_id, destination_region_id, dispatched_at, arrives_at, status: in_transit|delivered|intercepted)
- [ ] `TradeLedgerEntry` (world_id, caravan_id, sender_handle_at_send, receiver_handle, resource, amount, status, attacker_handle, recorded_at) — permanent for round, archived with world

### Services
- [ ] `Caravans::Dispatch.call(sender, receiver, payload, escort)` — validate capacity = sum of escort, deduct, schedule arrival
- [ ] `Caravans::Intercept.call(caravan, attacker_army)` — combat between attacker and escort; on success, payload transferred to attacker home stockpile (capped by capacity), recorded with attribution per `§12`
- [ ] `Caravans::Deliver.call(caravan)` — payload to receiver stockpile (Warehouse capped)
- [ ] Ledger writes on every dispatch / delivery / interception

### API endpoints
- [ ] `POST /v1/kingdoms/:id/caravans` — `send <player> <amount> <resource>`
- [ ] `GET  /v1/worlds/:id/trade-ledger` — pagination, optional `player`, `since` filters

### Tests
- [ ] Escort capacity gates payload size
- [ ] Interception attribution: both sender and interceptor visible (per `§12`); caravan interception always attributed even when scout intel is anonymous
- [ ] Warehouse cap respected on delivery (excess lost? — keep consistent with Ruin claim)
- [ ] Ledger immutable, world-scoped

---

## Phase 9 — Wonder Mechanics

Implements `§14` and `§16.2`. Round-end critical path.

### Models
- [ ] `Wonder` (kingdom_id, name, status: foundation|construction|consecration|completed|destroyed, hp, target_hp, started_at, phase_change_at, milestones_paid jsonb)
- [ ] `WonderDamageEvent` (wonder_id, attacker_kingdom_id, hp_before, hp_after, battle_id, occurred_at)

### Services
- [ ] `Wonders::Prerequisites.call(kingdom)` — building levels, ≥3 controlled nodes, unlock cost equal to Foundation payment (`§14`/`§16.2`)
- [ ] `Wonders::Start.call(kingdom, wonder_name)` — deduct 25% upfront, lock build queue (no other building upgrades) per `§14`, fire world announcement, HP=1000
- [ ] `Wonders::ApplyConstruction` (tick): +100 HP/h to 10,000 across 90h
- [ ] `Wonders::Milestone.call(wonder, percent)` — at 25/50/75% completion, demand 10% payment; pause construction until paid
- [ ] `Wonders::Damage.call(wonder, trebuchet_count_surviving)` — `-50 HP × trebuchets` per attack; if HP reaches 0 → `Wonders::Destroy.call` (resources lost, queue unlocked, builder may restart)
- [ ] `Wonders::Repair.call(wonder, hp)` — 1 HP per 8 Stone, cap 2000 HP per phase, pause construction 30 min per 500 HP repaired
- [ ] `Wonders::EnterConsecration.call(wonder)` — pay 5%, 24h timer scheduled, world announcement
- [ ] `Wonders::Complete.call(wonder)` — if Consecration ends with HP>0 → trigger round end
- [ ] No new weather windows scheduled once Consecration begins (`§16.11`)

### API endpoints
- [ ] `GET  /v1/kingdoms/:id/wonder` (status, HP, milestone, ETA)
- [ ] `POST /v1/kingdoms/:id/wonder` — `{name}` (start)
- [ ] `POST /v1/kingdoms/:id/wonder/repair` — `{hp}`
- [ ] `POST /v1/kingdoms/:id/wonder/cancel`
- [ ] `GET  /v1/worlds/:id/wonders` (public list)

### Tests
- [ ] Foundation payment exact: 25% per `§16.2` table
- [ ] Milestone payments freeze construction when missed
- [ ] Trebuchet damage = 50 × surviving units
- [ ] Repair cap 2000 HP per phase enforced independently per phase
- [ ] Consecration timer scheduled correctly, world announcement fired
- [ ] Destruction restart loses all paid resources
- [ ] Build queue locked during construction; unit training continues
- [ ] No weather windows spawn during Consecration (active ones run to scheduled end)

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
