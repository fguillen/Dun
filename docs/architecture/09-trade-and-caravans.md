# 09 — Trade, Caravans & Ledger

Phase 8 of [TODO.md](../../TODO.md). Adds player-to-player resource trade via escorted caravans (`§12`) and a world-scoped public trade ledger (`§17.2`). The anti-collusion mechanic is visibility, not prohibition: every transfer is recorded with sender, receiver, resource, amount, and outcome, viewable by any member of the world's server.

Caravans piggyback on the existing march/combat/scheduled-event stack from Phases 5–7. [`MarchOrder.intent`](../../app/models/march_order.rb) already included `caravan`; `march_orders.cargo` and `escort_units` jsonb columns already existed. Phase 8 adds the `caravan_return` intent, the [`Caravan`](../../app/models/caravan.rb) and [`TradeLedgerEntry`](../../app/models/trade_ledger_entry.rb) tables, the lifecycle services, and the public read endpoints.

---

## What ships in this phase

| Concern | Service | Notes |
|---|---|---|
| Caravan dispatch | [`Caravans::Dispatch`](../../app/services/caravans/dispatch.rb) | splits escort, deducts payload, fires a `caravan`-intent march |
| Arrival routing | [`Caravans::Arrive`](../../app/services/caravans/arrive.rb) | called by [`Marches::Arrive`](../../app/services/marches/arrive.rb); picks delivery vs. interception |
| Delivery + escort return | [`Caravans::Deliver`](../../app/services/caravans/deliver.rb) | credits receiver stockpile, schedules `caravan_return` retrace march |
| Third-party interception | [`Caravans::Intercept`](../../app/services/caravans/intercept.rb) | escort vs. hostile combat at destination; loot = caravan cargo |
| Escort-vs-explicit-defender combat | [`Combat::Resolve`](../../app/services/combat/resolve.rb) `defender_army:` override + [`Combat::ApplyEscortOutcome`](../../app/services/combat/apply_escort_outcome.rb) | skips walls/home bonus; no loot transfer (cargo handled by `Intercept`) |
| Escort merge-back | [`Caravans::CompleteReturn`](../../app/services/caravans/complete_return.rb) | merges return-march survivors into sender's home army |
| Ledger writes | [`TradeLedger::Record`](../../app/services/trade_ledger/record.rb) | one row per non-zero resource per caravan; status mutated on transitions |

Plus the player surface — see [api-endpoints.md](api-endpoints.md):

- `POST /v1/kingdoms/:kingdom_id/caravans`
- `GET  /v1/worlds/:world_id/trade-ledger` (paginated; `?player`, `?since`, `?limit`, `?page` filters)

---

## Caravan dispatch and lifecycle

A caravan is the *trade event*; its escort is an ordinary [`Army`](../../app/models/army.rb) that carries it, and its movement is an ordinary [`MarchOrder`](../../app/models/march_order.rb) with intent `caravan`. The [`Caravan`](../../app/models/caravan.rb) row binds them together with the sender/receiver kingdoms, the payload snapshot, and the escort composition snapshot.

```
sender_kingdom ─── Caravans::Dispatch ──► escort Army (split off source_army)
                            │                       │
                            ▼                       ▼
                Stockpile::Apply              MarchOrder(intent: caravan)
                (sender, -payload)            ScheduledEvent(kind: march_arrival)
                            │
                            ▼
                Caravan(status: in_transit) ──► TradeLedger::Record(in_transit)
                            │                          │
                            └── outbound_march_order ──┘
```

[`Caravans::Dispatch.call(sender_kingdom:, receiver_kingdom:, source_army:, payload:, escort_units:)`](../../app/services/caravans/dispatch.rb) validates everything that can fail synchronously — receiver in same world, not self-trade, receiver alive, payload has positive resource amounts, escort total carrying capacity ≥ sum of payload — then runs inside a transaction:

1. Deduct payload from sender's stockpile via [`Stockpile::Apply`](../../app/services/stockpile/apply.rb). Raises `InsufficientResources` if short.
2. Split the escort off `source_army` via [`Armies::Split`](../../app/services/armies/split.rb). The new escort army is named `Caravan N` (auto-incremented per kingdom).
3. Dispatch the escort with intent `caravan` via [`Marches::Dispatch`](../../app/services/marches/dispatch.rb). This computes the path (BFS on the region graph, slowest-unit speed, terrain modifiers per `§16.10`) and schedules the arrival `ScheduledEvent`.
4. Create the `Caravan` row with `status: in_transit`, linking the escort army and outbound march order.
5. [`TradeLedger::Record`](../../app/services/trade_ledger/record.rb) writes one in-transit row per non-zero resource in the payload, snapshotting both handles.
6. Emit `dun.caravan.dispatched`.

Status transitions are linear: `in_transit → delivered` or `in_transit → intercepted`. No reverse, no re-route. The Caravan record is permanent for the round (archived with the world per `§16.6`).

---

## Escort, cargo, and capacity

Escort units travel with the caravan. They protect the cargo on interception, and they retrace home after a successful delivery. The capacity rule is the same as the army carrying-capacity formula already used for combat loot (`§16.3`): each unit contributes its catalog `capacity` × count. Total escort capacity must be ≥ the sum of payload amounts — otherwise `Caravans::Dispatch` raises `InsufficientCapacity` before any DB write.

Capacity sample (from [`Units::Catalog`](../../app/services/units/catalog.rb)): `levy` 50, `archer` 30, `pikeman` 40, `knight` 80, `catapult` 200, `scout` 10, `royal_guard` 60, `trebuchet` 250.

There is no per-resource sub-cap — a 1-knight escort can carry 80 gold, or 80 wood, or any 80-unit combination.

---

## Arrival routing (deliver vs intercept)

When the outbound `march_arrival` event fires, [`Marches::Arrive`](../../app/services/marches/arrive.rb) routes intent `caravan` to [`Caravans::Arrive`](../../app/services/caravans/arrive.rb), which decides between delivery and interception:

```
caravan march arrives ──► Caravans::Arrive
                              │
                              ▼
        any third-party army at destination_region
        with status home/engaged and composition > 0?
                       │           │
                      yes          no
                       │           │
                       ▼           ▼
            Caravans::Intercept  Caravans::Deliver
            (strongest, ties     (credit receiver,
             broken by army.id)   schedule return)
```

"Third-party" excludes both the sender and the receiver — armies belonging to either are friendly and ignored. Hostiles in `marching` or `returning` status are also ignored (they're in transit themselves, not camped). Among camped hostiles, the strongest (highest total raw attack by [`Units::Catalog`](../../app/services/units/catalog.rb)) intercepts; ties break deterministically by the lowest `army.id`.

This means **a v1 interceptor must pre-position**: there's no scout intel (Phase 13), so the interceptor doesn't know about the caravan in advance. Interception is opportunistic — an army camped at a region happens to catch a caravan passing through.

---

## Combat at interception

The escort fights the hostile via [`Combat::Resolve`](../../app/services/combat/resolve.rb) with a Phase-8-added override:

```ruby
Combat::Resolve.call(
  march_order: caravan.outbound_march_order,   # the escort's march
  defender_army: hostile_army,                 # bypass region-home-kingdom lookup
  rng: rng
)
```

When `defender_army:` is supplied:
- The escort is the attacker (its march arrived); the hostile is the explicit defender.
- The region-home-kingdom defender aggregation is skipped — only the escort vs. only the hostile.
- Walls and home bonuses are suppressed (`is_defender_home: false`, `walls_level: 0`). The escort is "in the open."
- Terrain modifiers still apply via [`Combat::Round`](../../app/services/combat/round.rb), including marsh attacker −10% and the +25% defender terrain cap.
- The default loot pipeline (which would transfer from defender stockpile to attacker kingdom) is suppressed: [`Combat::ApplyEscortOutcome`](../../app/services/combat/apply_escort_outcome.rb) runs instead of [`Combat::ApplyOutcome`](../../app/services/combat/apply_outcome.rb), applying compositions and positions without the stockpile loot transfer.

[`Caravans::Intercept`](../../app/services/caravans/intercept.rb) then handles the cargo according to outcome:

| Outcome | Action |
|---|---|
| `attacker_victory`, `defender_rout` (escort wins) | Falls through to `Caravans::Deliver` — cargo continues to receiver. |
| `defender_victory`, `attacker_rout` (hostile wins) | Cargo transferred to hostile's home kingdom, capped first by surviving hostile carrying capacity, then by hostile home Warehouse (`Stockpile::Apply` clamps excess silently per `§16.11`). |

Caravan flips to `intercepted` with `attacker_handle` set, ledger entries update in place, and `dun.caravan.intercepted` fires.

---

## Trade ledger and snapshots

Each caravan produces **one ledger row per non-zero resource** in its payload — a 2-resource caravan creates 2 rows. The shape mirrors the GDD's column list (`§17.2`): sender handle, receiver handle, resource, amount, status, timestamp, plus `attacker_handle` set only on interception.

Handles are **snapshotted at dispatch time** and stored as plain strings (not FKs). A player renaming their handle later does not retroactively rewrite ledger history. The snapshot lookup falls back to `[unknown]` for the rare case of a profile with no handle set.

Status mutates in place as the caravan progresses:

| Trigger | Effect on existing ledger rows |
|---|---|
| `Caravans::Dispatch` | inserts rows with `status: in_transit` |
| `Caravans::Deliver`  | updates rows to `status: delivered` |
| `Caravans::Intercept` (loss) | updates rows to `status: intercepted`, sets `attacker_handle` |

Aside from these three transitions, ledger rows are append-only — no deletion, no other mutation. The `(caravan_id, resource)` unique index enforces one-row-per-resource-per-caravan.

---

## Tick / event integration

Caravans use the existing `march_arrival` ScheduledEvent kind — no new event type. The outbound march arrives → `Marches::Arrive` routes intent `caravan` to `Caravans::Arrive`. On successful delivery, `Caravans::Deliver` schedules a second `march_arrival` event for the return retrace, with the new intent `caravan_return` introduced in this phase:

```ruby
return_order = MarchOrder.create!(
  army: escort,
  origin_region_id: caravan.destination_region_id,
  target_region_id: caravan.origin_region_id,
  intent: "caravan_return",
  path: outbound.path.reverse,
  dispatched_at: now,
  arrives_at: now + duration   # mirror outbound duration
)
```

When the return event fires, `Marches::Arrive` routes intent `caravan_return` to [`Caravans::CompleteReturn`](../../app/services/caravans/complete_return.rb), which:

1. Picks the sender's first home-status army at the origin region (excluding the escort itself and any garrison), if one exists.
2. Merges the escort's surviving composition into that host army, then destroys the escort `Army` row.
3. If no host army exists, the escort is converted in place into a home army at the origin under a stable `Returning Caravan` name.

Both `Caravan.escort_army_id` and `Caravan.outbound_march_order_id` are `ON DELETE SET NULL`: the caravan row is the historical anchor and outlives the operational rows it spawned. Combat that wipes the escort army cascades through `Army → MarchOrder dependent: :destroy` and the caravan's FKs nullify cleanly, preserving the ledger history.

---

### `dun.*` events emitted

| Event | Fired by | Payload keys |
|---|---|---|
| `dun.caravan.dispatched`  | [`Caravans::Dispatch`](../../app/services/caravans/dispatch.rb) | `world_id, caravan_id, sender_kingdom_id, receiver_kingdom_id, payload, escort_units, arrives_at` |
| `dun.caravan.delivered`   | [`Caravans::Deliver`](../../app/services/caravans/deliver.rb) | `world_id, caravan_id, sender_kingdom_id, receiver_kingdom_id, payload` |
| `dun.caravan.intercepted` | [`Caravans::Intercept`](../../app/services/caravans/intercept.rb) | `world_id, caravan_id, sender_kingdom_id, receiver_kingdom_id, interceptor_kingdom_id, battle_id, loot_taken` |
| `dun.caravan.returned`    | [`Caravans::CompleteReturn`](../../app/services/caravans/complete_return.rb) | `world_id, caravan_id, sender_kingdom_id` |

Battle resolutions during interception still emit `dun.battle.resolved` and `dun.battle.applied` as usual.

---

## What this phase does not do

- **No interception of in-transit caravans on path regions.** Interception only fires on arrival at the destination. Phase 13 (fog of war + scouting) and a future enhancement could add intent-targeted intercept marches.
- **No marketplace / order book.** Per `§12`, direct caravan trade is the only v1 mechanic.
- **No raid cap or rate limit on dispatch.** Phase 11 (anti-abuse) wires the global write rate limits and per-pair raid cap; trade dispatch will pass through the standard write-limit budget when that ships.
- **No ledger archive endpoint.** Ledger rows are scoped to the world and persist alongside it; the round archive (`§16.6`, Phase 10) will snapshot the ledger as part of the frozen world state.
