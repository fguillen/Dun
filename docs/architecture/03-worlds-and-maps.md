# 03 — Worlds & Maps

Phase 2 of [TODO.md](../../TODO.md). A **world** is one round of play inside a server, with a deterministic map and a finite lifecycle. This file covers the state machine, the map generation pipeline, kingdom bootstrap, and late-joiner mechanics.

The mental anchor: everything in this layer is **scoped to a single world**. Worlds are independent of each other; archiving one doesn't touch another.

---

## The world state machine

```
            ┌──────────────┐
            │   proposed   │ (admin has created the world; T0 is in the future)
            └──────┬───────┘
                   │ Worlds::StartJob fires at t0_at
                   │ AND kingdoms.count >= min_players
                   ▼
            ┌──────────────┐
            │    grace     │ (map generated, kingdoms placed, 72h late-joiner window)
            └──────┬───────┘
                   │ Worlds::EndGraceJob fires at grace_closes_at (t0+72h)
                   ▼
            ┌──────────────┐
            │    active    │ (full game; late-joiners no longer allowed)
            └──────┬───────┘
                   │ Wonder completes (Phase 9, not shipped)
                   │ OR Rounds::End (Phase 10, not shipped)
                   ▼
            ┌──────────────┐
            │   archived   │ (frozen; read-only; archive endpoint serves the snapshot)
            └──────────────┘

            ┌──────────────┐
   ─────────│  cancelled   │ (terminal; from `proposed` only, via admin or housekeeping)
            └──────────────┘
```

`World::STATUSES` and `LIVE_STATUSES` are defined in [app/models/world.rb](../../app/models/world.rb#L2). Each status has a predicate (`world.proposed?`, etc.).

### Time anchors

A `World` row has four datetime columns that anchor the state machine:

| Column | Set when | Meaning |
|---|---|---|
| `t0_at` | at propose, mutable until start | Scheduled start of the round |
| `grace_closes_at` | at start | `t0_at + 72h`; when late-joiner admission closes |
| `archived_at` | at archive | Frozen state from this moment |
| `cancelled_at` | at cancel | Terminal abort |

`auto_cancel_after_hours` (default 168h = 7 days) is the housekeeping safety net: a `proposed` world that hasn't reached `min_players` by `created_at + auto_cancel_after_hours` is auto-cancelled. See [Worlds::HousekeepingJob#auto_cancel_stale_proposed_worlds](../../app/jobs/worlds/housekeeping_job.rb#L17).

---

## Lifecycle services

Each transition has a single service. Controllers and jobs both delegate to them.

| Service | Trigger | What it does |
|---|---|---|
| [Worlds::Propose](../../app/services/worlds/propose.rb) | `POST /v1/admin/servers/:id/worlds` | Creates the world (`status: "proposed"`, fresh seed, enqueues `Worlds::StartJob`) |
| [Worlds::Configure](../../app/services/worlds/configure.rb) | `PATCH /v1/admin/worlds/:id` | Edits a proposed world; re-enqueues `StartJob` if `t0_at` changes |
| [Worlds::Cancel](../../app/services/worlds/cancel.rb) | `POST /v1/admin/worlds/:id/cancel` | Only valid in `proposed`; sets `status: "cancelled"` |
| [Worlds::Join](../../app/services/worlds/join.rb) | `POST /v1/worlds/:id/join` | Player joins (proposed → adds kingdom; grace → calls `AssignLateJoiner`) |
| [Worlds::Start](../../app/services/worlds/start.rb) | `Worlds::StartJob` at `t0_at` | Generates map, places T0 kingdoms, transitions to `grace` |
| [Worlds::ForceStart](../../app/services/worlds/force_start.rb) | `POST /v1/admin/worlds/:id/start` | Admin override: transitions a `proposed` world to `grace` immediately, bypassing both the `t0_at` wait and the `min_players` check. Anchors `t0_at` and `grace_closes_at` to now |
| [Worlds::EndGrace](../../app/services/worlds/end_grace.rb) | `Worlds::EndGraceJob` at `grace_closes_at` | Releases unused spawn slots, transitions to `active` |
| [Worlds::Archive](../../app/services/worlds/archive.rb) | (Phase 10, stub today) | Active → archived |

### Concurrent-world limit

[Worlds::Propose#enforce_concurrent_limit!](../../app/services/worlds/propose.rb#L46) blocks a new proposal if the server already has `max_concurrent_worlds` live worlds (`proposed`/`grace`/`active`). `max_concurrent_worlds: 0` disables world creation entirely — a kill switch for an operator who wants to freeze their server.

### Locking on transitions

`Worlds::Start` and `Worlds::EndGrace` both wrap their transition in `ActiveRecord::Base.transaction { World.lock.find(id); ... }`. This matters because the recurring [Worlds::HousekeepingJob](../../app/jobs/worlds/housekeeping_job.rb) also calls these services as a safety net (in case `StartJob`/`EndGraceJob` was delayed or never ran), and a non-locked path could double-start a world.

The early-return `return world unless world.proposed?` (and similar) makes the transition idempotent: if it's already happened, do nothing. This also keeps the orphaned `Worlds::StartJob` enqueued at the original `t0_at` harmless after an admin force-start — it fires later, finds the world already in `grace`, and no-ops.

### Housekeeping safety net

[Worlds::HousekeepingJob](../../app/jobs/worlds/housekeeping_job.rb) runs hourly and:

1. Auto-cancels proposed worlds past `auto_cancel_after_hours` that never reached `min_players`.
2. Eagerly starts overdue proposed worlds (in case `StartJob` was lost).
3. Closes overdue grace windows (in case `EndGraceJob` was lost).
4. Reaps `processed_at` scheduled events older than 7 days.

Recurring Solid Queue jobs can fail to fire if the worker is down; the housekeeping job is the deterministic catch-up.

---

## The world map

A world's map is generated **once**, at `Worlds::Start`, from `world.seed`. The seed is a 16-character hex string fixed at propose time (`SecureRandom.hex(8)`). Same seed ⇒ identical map every time. That property is load-bearing for tests (a snapshot test against a fixed seed catches regressions in map gen).

### Domain tables

| Table | Owns | Notes |
|---|---|---|
| [regions](../../app/models/region.rb) | one row per node in the map graph | `terrain` ∈ {plains, forest, hills, mountain, marsh}, `spawn_eligible` boolean, `position: { x, y }` normalized to [0,1] |
| [region_adjacencies](../../app/models/region_adjacency.rb) | undirected edges | canonical-ordered: `region_a_id < region_b_id` enforced by validation |
| [nodes](../../app/models/node.rb) | resource sites | one or two per region; tiers `poor`/`standard`/`rich`; `is_home_hoard` flag; wilderness garrison if unclaimed |
| [ruins](../../app/models/ruin.rb) | dungeon-like one-shot caches | one per region max; tiers `minor`/`standard`/`major`; cache rewards on claim |
| [kingdoms](../../app/models/kingdom.rb) | per-player foothold | `stockpiles` jsonb (G/W/S/I + `checkpoint_at`); `home_region_id` set when spawned |

`Region::TERRAIN_MARCH_MOD` carries the march speed multiplier per terrain (used by [Marches::Plan](../../app/services/marches/plan.rb)) — see [06-military.md](06-military.md).

---

## The map generation pipeline

[MapGeneration::Generate](../../app/services/map_generation/generate.rb) is a five-stage chain, all inside one DB transaction, all seeded from one `Random.new(world.seed_int)` so the whole pipeline is deterministic.

```
seed
 │
 ▼
BuildGraph        ── creates Region rows + RegionAdjacency edges (planar graph)
 │
 ▼
AssignTerrain     ── Voronoi clusters each region to one of 5 terrains
 │
 ▼
PlaceSpawns       ── picks spawn-eligible regions + places home-hoard nodes
 │
 ▼
PlaceNodes        ── places resource nodes biased to thematic terrain
 │
 ▼
PlaceRuins        ── places dungeon caches with 2-hop spacing
```

### Stage 1 — BuildGraph

[MapGeneration::BuildGraph](../../app/services/map_generation/build_graph.rb).

- **Region count**: `clamp((2.5 × players_count + 6).round, 16, 64)` per `§16.5`.
- **Points**: sampled in `[0,1]²` with a min-distance constraint (`(0.65/√n)²`) — Poisson-disk-ish blue noise.
- **Edges**: Delaunay triangulation via the in-tree [Dun::Delaunay](../../lib/dun/delaunay.rb) (Bowyer-Watson) implementation. The Delaunay gives a planar triangulation; we then prune longest edges to land in average-degree 2.8–3.5, while never dropping any region below degree 2.
- **Names**: pulled from [db/seed_data/region_names.yml](../../db/seed_data/region_names.yml), shuffled with the seeded RNG.
- **Hubs**: any region of degree ≥ 5 is flagged `is_hub: true`. Hubs matter for spawn eligibility (you cannot spawn _at_ a hub but you might be near one).

Both `Region` and `RegionAdjacency` are inserted via `insert_all!` for speed; ULIDs are generated by the service.

### Stage 2 — AssignTerrain

[MapGeneration::AssignTerrain](../../app/services/map_generation/assign_terrain.rb).

- Builds a pool of "seed terrains" sized to target shares (`plains: 0.40, forest: 0.20, hills: 0.20, mountain: 0.12, marsh: 0.08`) divided by a cluster size of 4.
- Picks random regions as seeds, assigns each seed a terrain from the pool.
- Every other region is assigned the terrain of its nearest seed (Euclidean), producing **Voronoi clusters** of terrain.

The result: contiguous biomes rather than salt-and-pepper noise. This makes the map visually coherent and gives thematic node placement (mountains for stone/iron) something to bias against.

### Stage 3 — PlaceSpawns

[MapGeneration::PlaceSpawns](../../app/services/map_generation/place_spawns.rb) — the most constraint-heavy stage.

Goal: pick up to `ceil(players × 1.5)` spawn-eligible regions ("slots"). The extra 50% headroom is for late-joiners during the grace window.

Constraints (all from `§16.5` and `§16.8`):

- Terrain must be `plains` or `hills`.
- Degree must be in `2..4` (not too cramped, not a hub).
- Spawn must have ≥ 2 wilderness (non-spawn) neighbors.
- Min 2-hop spacing between spawns.

Algorithm: max-min Poisson-disk on the region graph — pick the candidate that is _furthest_ (by hops) from existing spawns, then iterate.

If the strict constraints can't yield enough slots, [satisfies_relaxed?](../../app/services/map_generation/place_spawns.rb#L100) widens them in three steps, **in this order**:

1. `:none` — strict (terrain ∩ degree 2–4 ∩ ≥2 wilderness neighbors).
2. `:degree` — relax degree to `2..5` (allow degree-5 hubs).
3. `:wilderness` — relax wilderness-neighbor count.

**Terrain is never relaxed.** That property is tested.

The relaxation only kicks in for nasty seeds. If even `:wilderness` doesn't yield any slot, the service raises `MapGeneration::InfeasibleSeed` and `Worlds::Start` will surface it. In practice a `WARN` log at `:wilderness` (`event: "map_generation.spawn_relaxation_short"`) is fired with `world_id` and `seed` so you can investigate the seed.

After spawns are picked, [place_home_hoards](../../app/services/map_generation/place_spawns.rb#L158) drops one `is_home_hoard: true` Node per spawn region. The home-hoard resource is the one in the **weakest** supply among the spawn's neighbors — keeps every spawn economically viable per `§16.5`.

### Stage 4 — PlaceNodes

[MapGeneration::PlaceNodes](../../app/services/map_generation/place_nodes.rb).

- **Count**: `round(1.2 × players_count)`.
- **Tier distribution**: 20% rich, 50% standard, 30% poor.
- **Resource distribution**: 35% stone, 25% iron, 20% wood, 20% gold.
- **Thematic bias**: 70% chance to place a stone/iron node in mountain/hills, wood in forest, gold in plains/hills. The other 30% goes anywhere eligible — this is the "wildcard" that keeps maps non-formulaic.

Per-region constraints:

- ≤ 2 nodes total per region.
- A `rich` node cannot coexist with any other node in the same region.
- A `rich` node cannot be in a region adjacent to a spawn (anti-snowball — `§16.5`).

Spawns themselves are excluded from node placement; spawns get their own home-hoard from stage 3.

Wilderness garrisons (`Node::WILDERNESS_GARRISONS`) are seeded into `garrison` jsonb at insertion. These are the troops a kingdom must defeat to capture the node (Phase 7).

### Stage 5 — PlaceRuins

[MapGeneration::PlaceRuins](../../app/services/map_generation/place_ruins.rb).

- **Count**: `max(2, round(players_count / 4))`.
- **Tier distribution**: 50% minor, 35% standard, 15% major.
- Excludes mountain and marsh terrain.
- Excludes regions that already have a node, and spawn regions.
- Min 2-hop spacing between ruins (BFS distance).

Each ruin gets a `garrison` (to defeat on claim) and a `cache` (rewards on success), shaped per [Ruin::GARRISONS](../../app/models/ruin.rb#L4) and [Ruin::CACHES](../../app/models/ruin.rb#L10).

---

## Kingdom bootstrap

[Kingdoms::Bootstrap](../../app/services/kingdoms/bootstrap.rb) is what makes a `Kingdom` row playable. It is called both from `Worlds::Start` (for everyone who joined pre-T0) and from `MapGeneration::AssignLateJoiner` (during the grace window).

What it does:

1. Computes the late-joiner bonus: `(hours_since_t0 / 12) × 1000`, capped at 4000.
2. Seeds the stockpile: `500 + bonus` of each of gold/wood/stone/iron, plus `checkpoint_at = now`. The `checkpoint_at` is critical — every read of the stockpile is `last + elapsed × rate` from this anchor.
3. Writes starter metadata into `kingdom.metadata`: starter buildings, starter levy count, bonus, hours.
4. Materializes one [Building](../../app/models/building.rb) row per kind in [Buildings::Catalog::KINDS](../../app/services/buildings/catalog.rb#L3) — most at level 0, a handful at level 1 per `Kingdoms::Bootstrap::STARTER_BUILDINGS`.

The starter levy (20 units) is **not** materialized as an Army yet — Phase 5 creates the `Garrison` army on-demand when the first training order completes. See [06-military.md](06-military.md).

### The pre-T0 kingdom stub

When a player joins a proposed world, [Worlds::Join](../../app/services/worlds/join.rb#L27) creates a `Kingdom` row with `home_region_id: nil`. This is a **stub**:

```ruby
def stub?
  home_region_id.nil?
end
```

Stub kingdoms have no buildings, no stockpile, no map presence. They exist only to count toward `min_players` and to remember who pre-registered. At `Worlds::Start`, every stub kingdom is matched to a spawn region in `joined_at` order via `MapGeneration::AssignLateJoiner` with `hours_since_t0: 0`, which calls `Kingdoms::Bootstrap` to fill it in.

The [home_region_required_after_proposed](../../app/models/kingdom.rb#L48) validation refuses to save a stub once the world has left `proposed`.

---

## The late-joiner flow

During the 72-hour grace window after T0, players can still join an `active`-ish world. Mechanics from `§16.8`:

1. **Bonus**: a player joining at T0+H gets a stockpile bonus of `(H/12) × 1000`, capped at 4000. Compensates for missed production.
2. **Spawn**: drawn from the leftover spawn slots that `PlaceSpawns` reserved.

[MapGeneration::AssignLateJoiner](../../app/services/map_generation/assign_late_joiner.rb):

1. Picks a spawn region not yet claimed by another kingdom, using a per-profile RNG `Random.new(world.seed_int ^ Zlib.crc32(profile.id))`. The deterministic-per-profile seed is what makes a given player always land in the same region for the same world if everything else is equal — handy for replay.
2. Calls `Kingdoms::Bootstrap` with `hours_since_t0`.

`Worlds::Join` computes `hours_since_t0 = ((now - t0_at) / 1.hour).floor` for grace-window joiners.

### Closing the grace window

At `grace_closes_at`, [Worlds::EndGrace](../../app/services/worlds/end_grace.rb) flips `spawn_eligible` to `false` on every region not yet claimed. The world transitions to `active` and emits `dun.world.grace_closed` on the [internal event bus](05-tick-engine.md#the-dun-event-bus).

Late joiners after this point are rejected by [Worlds::Join](../../app/services/worlds/join.rb#L18) with `WorldNotJoinable`.

---

## Player-facing read endpoints

| Endpoint | Purpose |
|---|---|
| `GET /v1/servers/:id/worlds` | List every world on a server you belong to (lean — no `my_kingdom`, no counts), ordered `t0_at` desc; 404 to non-members |
| `GET /v1/worlds/:id` | World summary: status, region count, kingdom count, your kingdom summary |
| `GET /v1/worlds/:id/map` | Full map: regions + adjacencies. Large but cacheable. |
| `GET /v1/worlds/:id/regions/:region_id` | One region's detail |
| `GET /v1/worlds/:id/regions/:region_id/adjacent` | Adjacent region IDs |
| `GET /v1/worlds/:id/ruins` | All ruins, claimed and unclaimed |

Admin endpoints for world configuration are listed in [api-endpoints.md](api-endpoints.md).

---

## Determinism, in two short bullets

- `world.seed` is set once at propose time and is the only source of randomness for map generation. Two worlds with the same seed and same `players_count` produce byte-identical regions/adjacencies/nodes/ruins. Tests pin a seed to assert this.
- Late-joiner spawn pick uses `world.seed_int ^ crc32(profile.id)`. So for a fixed world and a fixed profile, the spawn region is fixed — but two different profiles in the same world won't collide on the RNG.

---

## Open seams for later phases

- `Worlds::Archive` is implemented but is only called from Phase 10's `Rounds::End` (not shipped). The `winner_kingdom_id` and `wonder_name` columns are already in the schema for that purpose.
- `Node` and `Ruin` capture/claim logic (Phase 7) will read from the `garrison`/`cache` jsonb already in place from map gen.
- The `WorldInvitation` model exists but is informational only — admission is still gated by `ServerAccess`. Phase 11 may upgrade it into a real access channel.
