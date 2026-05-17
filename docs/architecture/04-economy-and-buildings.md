# 04 — Economy & Buildings

Phase 3 of [TODO.md](../../TODO.md). Resource production, the build queue, the cost/time formulas, and the Stone Mason discount mechanic. This is also where the **lazy stockpile accrual** pattern is established — a load-bearing design choice that every later phase builds on.

The mental anchor: **resource state is never updated continuously**. It is a tuple `(checkpoint_stockpile, checkpoint_at)` plus a derivation function. Reads project forward; writes re-anchor.

---

## The lazy stockpile

Naïvely you might increment a kingdom's gold every second by its gold rate. With N kingdoms across M worlds, that's N×M writes per second, a brutal scaling problem.

dun's approach: **store the snapshot, derive the present**.

`kingdoms.stockpiles` is a jsonb column shaped like:

```json
{
  "gold": 1500,
  "wood": 1200,
  "stone": 800,
  "iron": 600,
  "checkpoint_at": "2026-05-15T14:30:00Z"
}
```

Two operations matter:

### `Stockpile::Read.call(kingdom)` — pure projection, no writes

[app/services/stockpile/read.rb](../../app/services/stockpile/read.rb).

```
stockpile[r] = min(
  checkpoint[r] + Production::RateFor(r) * (now - checkpoint_at) / 3600,
  warehouse_cap
)
```

Used by `GET /v1/kingdoms/:id` and anywhere read-only display is needed. Zero writes, safe to call constantly.

### `Stockpile::Apply.call(kingdom:, deltas:)` — atomic write with cap & insufficiency

[app/services/stockpile/apply.rb](../../app/services/stockpile/apply.rb).

1. `SELECT ... FOR UPDATE` on the kingdom row.
2. Project the present using `Stockpile::Read`.
3. Add the deltas to each resource.
4. If any goes negative, raise `Stockpile::Apply::InsufficientResources` with the short-by amount.
5. Clamp to `Buildings::Catalog.warehouse_cap(warehouse_level)` (excess production is **hard-stopped**, not banked).
6. Persist new values + `checkpoint_at = now`.

Every state-changing path (queueing a build, training units, future combat loot, future caravan dispatch) goes through `Stockpile::Apply`. Negative deltas spend, positive deltas refund or loot.

[Stockpile::Checkpoint](../../app/services/stockpile/checkpoint.rb) is `Apply` with empty deltas — used by the production checkpoint job (Phase 4) to flush accrual to disk periodically so the projection is bounded.

### Warehouse cap

The cap is `WAREHOUSE_BASE_CAP + WAREHOUSE_LEVEL_COEFF × level²`, defined in [Buildings::Catalog](../../app/services/buildings/catalog.rb#L88):

```ruby
def self.warehouse_cap(level)
  WAREHOUSE_BASE_CAP + WAREHOUSE_LEVEL_COEFF * (level**2)
end
```

At level 0 the cap is 5,000 of each resource; at level 5 it's 5,000 + 2,500×25 = 67,500.

The cap is a **hard stop**, per `§16.4`. Excess production above the cap is silently lost. This means upgrading the warehouse early is a real strategic decision, not just a number-go-up.

---

## Production rates

[Production::RateFor.call(kingdom:, resource:)](../../app/services/production/rate_for.rb) returns hourly output:

```
rate = (base_rate_for_building × building_level) + sum(owned_node.base_rate for resource)
```

Base rates per building come from [Buildings::Catalog::PRODUCTION_BASE_RATES](../../app/services/buildings/catalog.rb#L50):

| Resource | Building | Base rate / level |
|---|---|---|
| gold | gold_mint | 30 |
| wood | lumber_camp | 40 |
| stone | quarry | 25 |
| iron | iron_mine | 30 |

A kingdom with a level-3 gold_mint produces 90 gold/h from the mint. If it also owns a `standard`-tier gold node (`base_rate: 250`), the total is 340 gold/h.

Node ownership is set by Phase 7 (`Nodes::Capture`, not yet shipped). For now every kingdom starts owning nothing — only the home-hoard sits in their home region as a wilderness node they need to capture.

---

## Buildings

Twelve building kinds, listed in [Buildings::Catalog::KINDS](../../app/services/buildings/catalog.rb#L3):

```
town_hall, gold_mint, lumber_camp, quarry, iron_mine, warehouse,
barracks, stable, siege_workshop, walls, watchtower, stone_mason
```

One [Building](../../app/models/building.rb) row per kingdom per kind. Materialized at kingdom bootstrap with starter levels per [Kingdoms::Bootstrap::STARTER_BUILDINGS](../../app/services/kingdoms/bootstrap.rb#L3). Levels run 0–20.

### Cost & time formulas

Both are geometric in level — costs grow faster than time so late upgrades become resource-bound, not time-bound.

[Buildings::CostFor](../../app/services/buildings/cost_for.rb):

```
cost(kind, L) = round(BASE_COSTS[kind] × 1.75^(L-1))
```

[Buildings::TimeFor](../../app/services/buildings/time_for.rb):

```
time(kind, L, kingdom) = min(BASE_TIMES[kind] × 1.55^(L-1), 24h) × (1 - stone_mason_discount)
```

The 24h cap is per `§16.4`: no single build takes more than a day, no matter how high the level.

### Stone Mason discount

The stone_mason building is a meta-upgrader. Each level reduces build time by 2%, capped at 30% (so levels above 15 stop helping):

```
discount = min(0.02 × stone_mason_level, 0.30)
```

The discount is applied at build-queue time and at completion — when a `stone_mason` upgrade _itself_ completes, [Buildings::Complete#recalc_in_progress_siblings](../../app/services/buildings/complete.rb#L47) re-prices the `completes_at` of every other in-progress build order and reschedules its `ScheduledEvent`. This is the only place in the codebase that **mutates a scheduled event's `fire_at`** rather than cancelling-and-rescheduling.

---

## The build queue

[Buildings::Queue](../../app/services/buildings/queue.rb) is the entry point: `POST /v1/kingdoms/:id/build` with `{building, target_level}`.

What it does, in order:

1. Locks the kingdom (`Kingdom.lock.find`).
2. Validates the building kind, the world is in `grace`/`active`, the kingdom is not eliminated.
3. Calls [Buildings::ResolveCompletions](../../app/services/buildings/resolve_completions.rb) first — this is the **lazy resolve** pattern (see below).
4. Asserts `target_level == building.level + 1` (one level at a time; no skipping).
5. Asserts target_level ≤ MAX_LEVEL (20).
6. **Idempotent retry**: if an in-progress order for the same `(building, target_level)` exists, return it.
7. Enforces tier gates (see below).
8. Enforces the queue-slot rule (see below).
9. Deducts cost via `Stockpile::Apply`.
10. Computes completion time, creates the `BuildOrder` row.
11. Schedules a `build_completion` `ScheduledEvent` at `completes_at`.

The order matters. The `ResolveCompletions` call (step 3) is what makes the rest of the logic correct: a ripe build order at the top of the queue might have been waiting for the discrete-event tick to drain it. Resolving it eagerly here means the slot count and the building's current level are up-to-date by the time we check them.

### Tier gates

From [Buildings::Catalog::TIER_GATES](../../app/services/buildings/catalog.rb#L64):

```
stable          requires barracks ≥ 3
siege_workshop  requires barracks ≥ 5  AND  iron_mine ≥ 5
```

Enforced by [enforce_tier_gates!](../../app/services/buildings/queue.rb#L77). Raises `TierGateUnmet`.

### Queue slot rule

By default a kingdom can have **one** build in flight. Town Hall unlocks more:

| Town Hall level | Slots |
|---|---|
| 0–9 | 1 |
| 10–19 | 2 |
| 20 | 3 |

Implemented in [enforce_queue_slot!](../../app/services/buildings/queue.rb#L87). Raises `QueueFull`.

Unit training, by contrast, is **not** queue-slot-limited at the kingdom level — instead each of `barracks`/`stable`/`siege_workshop` has its own independent queue (see [06-military.md](06-military.md)).

### Cancel & refund

`DELETE /v1/kingdoms/:id/build/:order_id` calls [Buildings::Cancel](../../app/services/buildings/cancel.rb):

- Refunds 75% of the cost (floored per resource). Time is lost.
- Cancels the pending `ScheduledEvent` for the build.

### Completion

`Buildings::Complete` is called both eagerly (by `Buildings::ResolveCompletions` on read) and lazily (by the discrete-event tick draining the `build_completion` event):

1. Locks the order and the building.
2. Bumps `building.level = order.target_level`.
3. Marks `order.completed_at`.
4. Marks the matching `ScheduledEvent` processed.
5. If the building is a `stone_mason`, re-prices and reschedules every sibling in-progress order.
6. Emits `dun.build_order.completed`.

---

## The lazy-resolve pattern

This is the most important shape in the build queue (and it's mirrored in training and marches, see Phase 5).

```
       ┌─────────────────────┐
       │  ScheduledEvent.    │
       │  fire_at <= now     │
       └──────────┬──────────┘
                  │
       ┌──────────┼──────────┐
       │                     │
       ▼                     ▼
  Eager drain           Lazy drain
  (every 5s)            (on every read/write
   by tick job          of this kingdom)
       │                     │
       ▼                     ▼
            Buildings::Complete (idempotent)
                  │
                  ▼
            building.level bumped
            order.completed_at set
            ScheduledEvent.processed_at set
            dun.build_order.completed
```

Two callers, idempotent target.

**Why both?** The tick is "eventually consistent" — it runs every 5 seconds, so for up to 5 seconds after `completes_at` the order is technically ripe but unprocessed. If a player issues a write (e.g. queues the next build) in that window, the build queue must reflect the completion **first**, otherwise the slot count and tier gates are stale.

So every write path through this layer:

1. Calls `Buildings::ResolveCompletions` (or `Training::ResolveCompletions`, or `Marches::ResolveArrivals`) for the affected kingdom.
2. Then reads fresh state.
3. Then proceeds.

`Buildings::Complete` is idempotent (the early `return order if order.resolved?` makes a double-call harmless), so the eager and lazy paths can race safely.

The lazy path is also a correctness fallback: even if the Solid Queue worker is down, the next time a player touches their kingdom, their orders catch up.

---

## What happens when a request lands

```
POST /v1/kingdoms/:id/build  { building: "barracks", target_level: 4 }
   │
   ▼
Api::KingdomsController#build
   │
   ▼
Buildings::Queue.call(kingdom: kingdom, kind: "barracks", target_level: 4)
   │
   ├── lock kingdom row
   ├── Buildings::ResolveCompletions ── drains ripe build orders
   ├── validate (kind, target_level, world status, eliminated)
   ├── Stockpile::Apply ── deduct cost (re-anchors checkpoint_at)
   ├── BuildOrder.create!
   └── ScheduledEvents::Schedule ── "build_completion" at completes_at
                                     emits dun.scheduled_event.created
   ▼
render BuildOrder JSON

(time passes)

DiscreteEventTickJob (every 5s)
   │
   ▼
ScheduledEvents::Drain ── pull ripe events with FOR UPDATE SKIP LOCKED
   │
   ▼
ScheduledEvents::Dispatch ── route by kind
   │
   ▼
Buildings::Complete.call(build_order)
   │
   ├── bump building.level
   ├── set order.completed_at
   ├── mark ScheduledEvent processed
   └── emit dun.build_order.completed
```

---

## Read endpoint

`GET /v1/kingdoms/:id` is served by [Api::KingdomsController](../../app/controllers/api/kingdoms_controller.rb). It returns:

- Resources (projected via `Stockpile::Read`)
- Production rates per resource (via `Production::RateFor`)
- Warehouse cap (via `Buildings::Catalog.warehouse_cap`)
- Buildings list with current levels
- In-progress build orders with `completes_at`
- (Phase 5) Armies, training orders

This endpoint is the workhorse of the CLI's `kingdom show` command — it's expected to be called frequently. Hence the lazy projection: every call is a small handful of reads, no writes (unless the player has ripe completions, which trigger a lazy resolve via subsequent writes — `GET` itself never mutates).

### Upgrade preview

`GET /v1/kingdoms/:id/build/preview?building=<kind>` is served by [Api::Kingdoms::BuildOrdersController#preview](../../app/controllers/api/kingdoms/build_orders_controller.rb) and delegates to `Buildings::UpgradePreview`. It composes the existing primitives:

- `Buildings::CostFor.call(kind:, level: current + 1)` → resource cost
- `Buildings::TimeFor.call(kind:, level: current + 1, kingdom:)` → duration after the Stone Mason discount
- `Stockpile::Read.call(kingdom)` → current stockpile, used to derive `affordable` and per-resource `missing`
- `Buildings::Catalog::TIER_GATES[kind]` → `tier_gates_unmet` list (same logic as `Buildings::Queue#enforce_tier_gates!`)

`Buildings::ResolveCompletions` runs first so `current_level` reflects any ripe orders.

**The preview is informational only.** It does *not* enforce world status, kingdom-eliminated, wonder-in-progress, or build-queue slot availability. `Buildings::Queue` still rejects those at commit time with the precise reason. Rationale: the preview answers "what would this cost?", which is useful even when "can I commit it right now?" is false. Splitting the two keeps the UI simple — render the cost, then let the POST do the gating.

At max level (`current_level >= Catalog::MAX_LEVEL`), `target_level`, `cost`, and `duration_seconds` are returned as `null` with `at_max_level: true`.

### Buildings list

`GET /v1/kingdoms/:kingdom_id/buildings` is served by [Api::Kingdoms::BuildingsController#index](../../app/controllers/api/kingdoms/buildings_controller.rb) and delegates to `Buildings::ListPreviews`. It returns one row per kind in `Buildings::Catalog::KINDS` (12 entries, sorted alphabetically). Each row is the `Buildings::UpgradePreview` payload — *the cost / duration / tier-gate / affordability logic is not duplicated* — with three fields merged on top:

- `id` — the `Building` row's id (`null` only on the rare bootstrap edge case where no row exists for the kind).
- `build_order` — the in-progress `BuildOrder` for that building (serialized via `Api::KingdomsController.serialize_build_order`), or `null`.
- `upgrade_possible` — `true` iff `!at_max_level && tier_gates_met && affordable && build_order.nil?`. The fourth clause mirrors `Buildings::Queue`'s rejection of a second order against the same building.

The endpoint accepts `?upgrade_possible=true` (also `1`) to narrow the result to actionable rows; any other value (including absent) returns the full list. The per-row shape is identical in both cases — the filter only narrows the array.

Like `build/preview`, `Buildings::ResolveCompletions` runs first so the snapshot reflects ripe builds. Rationale for the endpoint: clients (CLI, future UIs) need to render the "build" screen in one round trip; calling `build/preview?building=<kind>` twelve times in a loop is wasteful and races against tick state.

---

## Stretching, gotchas, anti-patterns

- **Never update `kingdom.stockpiles` directly.** Always go through `Stockpile::Apply`. Bypassing the service skips the warehouse cap, the insufficiency check, and the `checkpoint_at` re-anchor.
- **Don't read stockpile from `kingdom.stockpiles` either** — use `Stockpile::Read`. The stored values are stale by definition (last checkpoint, not now).
- **Building level mutations only via `Buildings::Complete`.** It is the single source of truth for "this build has resolved." Otherwise the matching `ScheduledEvent` stays pending and the lazy resolver tries to re-complete it.
- **The 24-hour time cap is per upgrade, not per queue.** A level-19 → 20 upgrade still caps at 24h, regardless of what's already queued.
- **Stone Mason discount applies retroactively to in-progress orders, but only when stone_mason itself completes.** If you queue a 10h order and then queue a stone_mason upgrade behind it, the first order does not get discounted retroactively until/unless the stone_mason ahead of it in the queue completes — which depends on the slot rules.
- **Warehouse cap is per-resource, not aggregate.** Each resource has its own ceiling.

---

## What's adjacent

- The Phase 4 [tick engine](05-tick-engine.md) is what drains build completions.
- Phase 5's [training pipeline](06-military.md) reuses the same `Stockpile::Apply` → `ScheduledEvent` → lazy-resolve shape, with `TrainingOrder` instead of `BuildOrder`. If you can read this doc, you can read that one.
- Phase 7 (not shipped) will hook node ownership transfers into `Production::RateFor` without changes — that function already sums `owned_nodes.base_rate`.
