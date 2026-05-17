# 06 — Military: Units, Training, March

Phase 5 of [TODO.md](../../TODO.md). Eight unit kinds, three independent training queues, the army state machine, and the march planner.

Combat resolution is Phase 6 (not shipped). For now, march arrivals with attack-ish intents end in a stub that parks the army at the target as `engaged`. The state shape is there for Phase 6 to plug in.

---

## The unit catalog

[Units::Catalog](../../app/services/units/catalog.rb) is a frozen module of static data — stats, costs, training times, training-building mapping.

Eight units:

| Unit | Atk | Def | HP | Speed | Capacity | Train time (base) | Trained at |
|---|---:|---:|---:|---:|---:|---:|---|
| levy | 4 | 6 | 10 | 0.5 | 50 | 45s | barracks |
| archer | 12 | 4 | 8 | 0.5 | 30 | 90s | barracks |
| pikeman | 8 | 18 | 16 | 0.4 | 40 | 180s | barracks |
| knight | 25 | 12 | 20 | 1.0 | 80 | 240s | stable |
| scout | 2 | 2 | 4 | 2.0 | 10 | 60s | stable |
| royal_guard | 30 | 35 | 40 | 0.5 | 60 | 1500s | stable |
| catapult | 40 | 8 | 30 | 0.25 | 200 | 1200s | siege_workshop |
| trebuchet | 20 | 6 | 50 | 0.2 | 250 | 2700s | siege_workshop |

Read the stats off [STATS](../../app/services/units/catalog.rb#L15) directly — every field (atk/def/hp/speed/capacity/cost/base_train_time) has a `_for(unit)` accessor.

The `TRAINS_AT` map says which building kind trains which units:

```ruby
TRAINS_AT = {
  "barracks"       => %w[levy archer pikeman],
  "stable"         => %w[knight scout royal_guard],
  "siege_workshop" => %w[catapult trebuchet]
}.freeze
```

`TERRAIN_IMMUNE = %w[knight scout]` — armies composed _entirely_ of terrain-immune units march at their unmodified speed. Even one non-immune unit drags the army back into terrain math.

---

## Training pipeline

Same shape as the build queue (Phase 3), with one important difference: **each training building has its own independent queue**. A kingdom can be training levy at the barracks, knights at the stable, and a catapult at the siege workshop, all at the same time. The Town Hall slot rule from buildings does **not** apply here — they are parallel.

### Training time

[Units::TrainingTimeFor](../../app/services/units/training_time_for.rb):

```
time_per_unit(unit, building_level) = base_train_time × (0.95)^(level - 1)
```

5% speedup per building level, compounding. A level-10 barracks trains levy in 45 × 0.95⁹ ≈ 28s per unit. The `TrainingOrder` records `count`, so total time is `count × time_per_unit` — orders are persisted as a single row, not exploded into per-unit orders.

### Training::Queue

[Training::Queue](../../app/services/training/queue.rb) is the entry point for `POST /v1/kingdoms/:id/train`:

1. Lock kingdom.
2. Validate unit/building/world status/count.
3. `Training::ResolveCompletions` (lazy resolve — same shape as builds).
4. Confirm the training building exists at level ≥ 1.
5. Confirm the unit can be trained at this building (`TRAINS_AT`).
6. Compute cost = `unit_cost × count`, deduct via `Stockpile::Apply`.
7. Compute total time = `time_per_unit × count`, create `TrainingOrder`.
8. Schedule a `training_completion` `ScheduledEvent` at `completes_at`.
9. Emit `dun.training_order.queued`.

`Training::Cancel` mirrors `Buildings::Cancel`: 75% refund of total cost (count-aware), cancels the scheduled event.

### Training preview

`GET /v1/kingdoms/:id/train/preview?building=&unit=&count=` is served by [Api::Kingdoms::TrainingOrdersController#preview](../../app/controllers/api/kingdoms/training_orders_controller.rb) and delegates to `Training::Preview`. It returns:

- `per_unit_cost`, `total_cost` — from `Units::Catalog.cost_for(unit)` × `count`
- `per_unit_seconds`, `total_seconds` — from `Units::TrainingTimeFor.call(unit:, building_level:)` × `count`
- `affordable`, `missing` — vs. `Stockpile::Read.call(kingdom)`
- `max_affordable_count` — `min(stockpile[r] // per_unit_cost[r])` across resources where the per-unit cost is positive. Useful UX hook for "train as many as I can afford".
- `building_built` and `unit_trainable_here` — advisory flags. `Training::Preview` reports cost regardless; the actual `Training::Queue` rejects the mismatched combo at commit.

`Training::ResolveCompletions` runs first so `building_level` (which feeds the time discount) reflects any ripe training. The same informational-only stance applies as in the building preview: the preview reports cost even when the world is not buildable or the kingdom is eliminated, and the POST is what enforces.

### Where do trained units go?

[Training::Complete](../../app/services/training/complete.rb#L37) merges the new units into a special `"Garrison"` army for that kingdom:

```ruby
def find_or_create_garrison(kingdom)
  existing = kingdom.armies
    .where(name: Army::GARRISON_NAME, location_region_id: kingdom.home_region_id)
    .first
  return existing if existing

  kingdom.armies.create!(
    name: Army::GARRISON_NAME,
    location_region_id: kingdom.home_region_id,
    status: "home",
    composition: {}
  )
end
```

The Garrison is the kingdom's default army. It always sits at the home region in status `home`. Completed training adds to it; players who want to march a subset call `Armies::Split` to peel a new army off. The Garrison itself is never destroyed by `Armies::Split` (see [Armies::Split#L42](../../app/services/armies/split.rb#L42)) — even when emptied — so the kingdom always has an army to receive subsequent training.

---

## Armies

[Army](../../app/models/army.rb) carries:

| Field | Notes |
|---|---|
| `kingdom_id` | parent |
| `name` | unique per kingdom, case-insensitive, ≤ 60 chars |
| `location_region_id` | current region |
| `status` | `home` / `marching` / `engaged` / `returning` |
| `composition` | jsonb: `{ "levy": 25, "archer": 10, ... }` |

Helpers on the model:

- `total_capacity` — sum of `Units::Catalog.capacity_for(unit) × count`, used by caravan/loot mechanics in later phases.
- `slowest_speed` — minimum `speed` across all units present. Defines the army's overall march speed.
- `all_terrain_immune?` — true iff every present unit is knight or scout.

### Garrison naming convention

`Army::GARRISON_NAME = "Garrison"` is reserved. Other armies cannot use this name (unique-per-kingdom enforces that). The Garrison is also the army that:

- Receives new units from training.
- Is never destroyed even if emptied (other armies are destroyed on empty-after-split).

### Split / Merge / Rename

| Service | When |
|---|---|
| [Armies::Split](../../app/services/armies/split.rb) | peel a new army off the source army. Both must be `home`. The new army starts at the source's region, status `home`. Source is destroyed if drained to empty (unless it's the Garrison). |
| [Armies::Merge](../../app/services/armies/merge.rb) | combine `from` into `into`. Both must be same kingdom, same region, both `home`. `from` is destroyed. |
| [Armies::Rename](../../app/services/armies/rename.rb) | renames; case-insensitive uniqueness scope checked. |

All three emit `dun.army.*` notifications.

---

## March planning

[Marches::Plan](../../app/services/marches/plan.rb) — pure computation, no writes. Returns a `Result` struct with `path: [region_ids]`, `total_seconds`, and `per_leg: [Leg]`.

### Pathfinding

BFS on the region adjacency graph, capped at 1000 visited nodes (a hard ceiling that catches pathological worlds). Returns the first shortest path found.

```ruby
def bfs_path
  return [@origin.id] if @origin.id == @destination.id
  # ... standard BFS over adjacency, reconstructing parent pointers
end
```

The BFS treats every edge as equal — distance is in **hops**, not Euclidean. The map is small (16–64 regions) so the BFS is fast.

### Leg timing

For each pair of adjacent regions in the path:

```
terrain_avg = (TERRAIN_MARCH_MOD[from] + TERRAIN_MARCH_MOD[to]) / 2
leg_seconds = (1.0 / (slowest_speed * terrain_avg)) * 3600
```

`TERRAIN_MARCH_MOD` lives on `Region`:

| Terrain | Modifier |
|---|---:|
| plains | 1.0 |
| forest | 0.8 |
| hills | 0.9 |
| mountain | 0.6 |
| marsh | 0.5 |

Higher modifier = faster. Mountain and marsh are the punitive terrains.

If the army is **all-terrain-immune** (every present unit is knight or scout), `terrain_avg` is forced to `1.0` regardless of actual terrain. This is the "cavalry rides through anything" rule from `§16.10`.

### Why "slowest unit defines the speed"

Mixed-composition armies move at their slowest member's pace. A knight (speed 1.0) tagged onto a pikeman (speed 0.4) army still moves at 0.4. Players who want fast strikes either:

- Build pure-cavalry armies (and benefit from terrain immunity too).
- Use scout-only armies for reconnaissance (Phase 13 will give those armies a special role).

---

## March lifecycle

```
        Army (home, at home region)
              │
              ▼
   Marches::Dispatch.call(army, target, intent)
              │
              │  Marches::Plan.call (compute path + duration)
              │  MarchOrder.create!  (path persisted, arrives_at set)
              │  army.status = "marching"
              │  ScheduledEvent("march_arrival", fire_at = arrives_at)
              │
              ▼
        Army (marching)
              │
       ───────┼─────── recall?
              │            │
              │            ▼
              │     Marches::Recall.call
              │        - cancel pending arrival event
              │        - clone path reversed
              │        - new arrives_at = now + elapsed
              │        - schedule the return arrival
              │        - army.status = "returning"
              │
              ▼
   (fire_at reached, ScheduledEvent dispatched)
              │
              ▼
   Marches::Arrive.call
              │
              │  intent: reinforce → status home, location = target
              │  intent: scout     → status returning, location = target
              │  intent: attack/capture/claim_ruin → status engaged (stub)
              │  intent: caravan   → status home, location = target (stub)
              │
              ▼
        Army (next status)
```

### Intents

`MarchOrder::INTENTS = %w[attack reinforce scout capture claim_ruin caravan]`. Each one means something different at arrival:

| Intent | Handler today | Phase that fills in |
|---|---|---|
| `reinforce` | parks the army at the target, status `home` | already complete |
| `scout` | parks `returning` at the target (so Phase 13 can chain a return) | Phase 13 (fog of war) |
| `attack` | calls `Combat::Resolve`; runs combat or walks in if no defender | Phase 6 ([07-combat.md](07-combat.md)) ✅ |
| `capture` / `claim_ruin` | parks `engaged` at the target | Phase 7 (nodes, ruins) |
| `caravan` | parks `home` at the target | Phase 8 (trade) |

[Marches::Arrive](../../app/services/marches/arrive.rb) holds the dispatch table; the stubs have comments pointing at which later phase will replace them. Replacing them is the only thing those phases need to do — the scheduling, event handling, and state transitions are already in place.

### Recall

[Marches::Recall](../../app/services/marches/recall.rb) is symmetric. It does not destroy the original order — it marks it `recalled_at`, then creates a fresh `MarchOrder` along the reversed path with arrival = `now + elapsed_so_far`. The reverse trip is the same length as the elapsed forward trip — no acceleration, no losses (v1 doesn't model attrition).

The recall **does not refund cargo or escort** because v1 doesn't have those concepts yet; Phase 8 (caravans) will add cargo handling.

---

## The full request → state path

```
POST /v1/kingdoms/:id/train  { building: "barracks", unit: "archer", count: 10 }
  → Api::Kingdoms::TrainingOrdersController#create
  → Training::Queue.call
      lock kingdom
      Training::ResolveCompletions (drain any ripe orders first)
      validate, deduct cost via Stockpile::Apply
      create TrainingOrder
      ScheduledEvents::Schedule("training_completion", at completes_at)
      emit dun.training_order.queued
  ⇒ TrainingOrder JSON

      ...time passes...

DiscreteEventTickJob → ScheduledEvents::Drain → ScheduledEvents::Dispatch
  → Training::Complete.call(training_order:)
      lock order; if resolved, exit
      find or create the Garrison army (at home region, status home)
      merge units into Garrison.composition
      mark order completed
      emit dun.training_order.completed

POST /v1/armies/:garrison_id/split  { name: "Strike Force", units: { archer: 10 } }
  → Api::ArmiesController#split
  → Armies::Split.call
      both armies must be home
      validate sufficiency
      drain units from Garrison
      create new Army with given units, same location, status home
      emit dun.army.split
  ⇒ { source: Garrison, new: strike_force }

POST /v1/armies/:strike_force_id/march  { target_region_id: ..., intent: "attack" }
  → Api::ArmiesController#march
  → Marches::Dispatch.call
      lock army; must be home; world must be grace/active
      Marches::Plan.call → path + arrival_seconds
      create MarchOrder
      army.status = "marching"
      ScheduledEvents::Schedule("march_arrival", at arrives_at)
      emit dun.march_order.dispatched

      ...time passes...

DiscreteEventTickJob → ... → Marches::Arrive.call
      handler dispatches by intent:
      attack → Combat::Resolve (real combat — see 07-combat.md)
      capture/claim_ruin → army.status = "engaged" (Phase 7 plugs node/ruin combat here)
      mark order arrived
      emit dun.march_order.arrived
```

---

## Read endpoints

| Endpoint | What it returns |
|---|---|
| `GET /v1/kingdoms/:id/armies` | List your kingdom's armies (composition, status, location) |
| `GET /v1/armies/:id` | One army's detail, including its active march order if any |

Both are served by [Api::ArmiesController](../../app/controllers/api/armies_controller.rb) and [Api::Kingdoms::ArmiesController](../../app/controllers/api/kingdoms/armies_controller.rb).

---

## Gotchas

- **The Garrison is special.** Don't try to delete it. `Armies::Split` knows to keep it around. If you write new code that destroys armies, exclude `army.garrison?`.
- **Empty armies are invalid for dispatch** (`Marches::Plan` raises `EmptyArmy`). Splits that would drain an army to zero are also rejected — they raise `EmptySplit`.
- **`composition` is jsonb with string keys.** A composition like `{"levy": 25, "archer": 10}` reads back as `{"levy" => 25, "archer" => 10}`. Don't compare keys with symbols.
- **March times use the slowest unit speed, period.** Even one slow unit (a single pikeman) tanks an otherwise-cavalry army's speed and breaks terrain immunity.
- **Recall returns along the original path's reverse.** It does not re-plan, which means if the world topology somehow changed mid-march (it can't today, but Phase 12 weather windows might effectively change it), the recall still uses the original adjacencies.
- **Training queues are per-building, not per-kingdom.** A player can saturate all three (barracks + stable + siege_workshop) at once. The `TrainingOrder` table just records them; it doesn't enforce a kingdom-wide slot count.

---

## What Phase 6 plugged into this layer

Combat has shipped — see [07-combat.md](07-combat.md). The seams it used:

1. **`Combat::Resolve`** replaced the body of `handle_combat_stub` for intent `attack` only. `capture` / `claim_ruin` still parks the army `engaged` — Phase 7 will plug `Nodes::Capture` / `Ruins::Claim` against the wilderness garrisons stored on `nodes.garrison` and `ruins.garrison`.
2. **`Battle` and `BattleParticipant` tables** were added; both `BattleParticipant.army_id` and `Battle.march_order_id` are `dependent: :nullify` so destroying an emptied army (Phase 5's cascade) does not orphan historical reports.
3. **Multi-attacker arrival** resolves sequentially via `ScheduledEvents::Drain`'s existing `(fire_at, id)` ordering — no Phase 6 code was needed for that.
