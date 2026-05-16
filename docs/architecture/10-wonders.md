# 10 — Wonders

Phase 9 of [TODO.md](../../TODO.md). Implements the round-end win condition defined in `§14` and `§16.2` of the [Game Design Document](../dun%20Game%20Design%20Document.v3.md): a player commits to building a Wonder, pays 25% upfront, builds it across 90 hours through three milestone payments, pays a final 5% to enter a 24-hour Consecration phase, and wins the round if it survives. Other players attack with Trebuchets (50 HP per surviving unit per successful attack); destruction loses all paid resources and unlocks the queue.

The Wonder reuses the existing combat path (Trebuchet damage is grafted onto [`Combat::Resolve`](../../app/services/combat/resolve.rb) just like Walls already are), the tick engine (a new `wonder_phase` `ScheduledEvent` kind), and the stockpile pipeline ([`Stockpile::Apply`](../../app/services/stockpile/apply.rb) for every payment). No bespoke job, no bespoke clock — Phase 9 is small in code surface, large in game weight.

---

## What ships in this phase

| Concern | Service | Notes |
|---|---|---|
| Names + cost table | [`Wonders::Catalog`](../../app/services/wonders/catalog.rb) | Six committed Wonder names; §16.2 cost totals and per-payment percentages |
| Prereq validation | [`Wonders::Prerequisites`](../../app/services/wonders/prerequisites.rb) | World active, building levels, ≥3 owned nodes, affordability |
| Foundation payment | [`Wonders::Start`](../../app/services/wonders/start.rb) | Locks build queue, deducts 25%, schedules +90h transition |
| Lazy HP accrual | [`Wonders::ApplyConstruction`](../../app/services/wonders/apply_construction.rb) | Pure on-demand projection — mirrors `Stockpile::Read` philosophy |
| Milestone payment | [`Wonders::PayMilestone`](../../app/services/wonders/pay_milestone.rb) | Auto-paused at threshold; explicit pay to resume |
| Consecration entry | [`Wonders::EnterConsecration`](../../app/services/wonders/enter_consecration.rb) | Scheduled at +90h; deducts 5%, schedules complete at +24h |
| Round end hook | [`Wonders::Complete`](../../app/services/wonders/complete.rb) | Archives the world (minimal stub; Phase 10 will replace) |
| Trebuchet damage | [`Wonders::Damage`](../../app/services/wonders/damage.rb) | Grafted into `Combat::Resolve` after `ApplyOutcome` |
| Destruction | [`Wonders::Destroy`](../../app/services/wonders/destroy.rb) | Flips status, cancels pending events |
| Repair | [`Wonders::Repair`](../../app/services/wonders/repair.rb) | 1 HP per 8 Stone; 2000 HP/phase cap; pause 30 min per 500 HP |
| Voluntary abandon | [`Wonders::Cancel`](../../app/services/wonders/cancel.rb) | Same effect as destruction; paid resources lost |
| Live-Wonder lookup | [`Wonders::LiveFor`](../../app/services/wonders/live_for.rb) | Used by `Buildings::Queue` lock and combat damage hook |

Plus the player surface (see [api-endpoints.md](api-endpoints.md)):

- `GET    /v1/kingdoms/:id/wonder`
- `POST   /v1/kingdoms/:id/wonder`
- `POST   /v1/kingdoms/:id/wonder/repair`
- `POST   /v1/kingdoms/:id/wonder/milestone`
- `DELETE /v1/kingdoms/:id/wonder`
- `GET    /v1/worlds/:id/wonders` (public list)

---

## Lifecycle

```
Wonders::Start (deduct 25%)
        │
        ▼
status="construction"   ApplyConstruction accrues 100 HP/h
hp=1_000               ┌──── auto-pause at 25/50/75% ──── PayMilestone (deduct 10%)
                      │
                      ▼
hp=10_000 (+90h)  Wonders::EnterConsecration (deduct 5%)
        │
        ▼
status="consecration"  (+24h)
        │           │
        ▼           ▼
   hp drops to 0   hp survives
        │           │
        ▼           ▼
status="destroyed"  Wonders::Complete → world archived
```

Foundation is "instant" per §14: `Wonders::Start` deducts the 25% payment and creates the row already in `construction` status (HP 1,000, target HP 10,000). The model column `status: "foundation"` exists for future use (the design doc keeps it as a named phase for narration / repair-cap accounting), but the live-state machine flows directly through construction.

A live Wonder is any row with status in `%w[foundation construction consecration]` (see [`Wonder::LIVE_STATUSES`](../../app/models/wonder.rb)). The partial unique index `index_wonders_on_kingdom_id_when_live` enforces at most one live Wonder per kingdom at the database level.

---

## Cost table (§16.2)

The committed numbers, mirrored in [`Wonders::Catalog`](../../app/services/wonders/catalog.rb):

| Payment | Gold | Wood | Stone | Iron | Percent |
|---|---|---|---|---|---|
| Foundation | 200,000 | 150,000 | 600,000 | 200,000 | 25% |
| Milestone (×3 at 25/50/75%) | 80,000 | 60,000 | 240,000 | 80,000 | 10% each |
| Consecration | 40,000 | 30,000 | 120,000 | 40,000 | 5% |

Stone at 3× the other resources is the dedicated late-game Quarry-node sink (§16.2 reasoning).

---

## Lazy HP accrual

Like `Stockpile::Read`, `Wonders::ApplyConstruction` is a **pure projection**: it does not need to be called on a per-minute tick. The Wonder's `last_construction_at` column anchors the last computation; any reader (the show endpoint, a damage event, a milestone payment, the +90h consecration transition) calls `ApplyConstruction` first to materialize current HP, then proceeds.

```
hp_now = min(
  hp_then + (now - max(last_construction_at, paused_until)) × 100/h,
  TARGET_HP
)
```

Milestone detection clamps HP at the threshold (2,500 / 5,000 / 7,500) when crossed and sets `pending_milestone_percent`; the next `ApplyConstruction` call is a no-op until the player calls `Wonders::PayMilestone`.

Repairs set `paused_until` (30 min per 500 HP, stackable); `ApplyConstruction` resumes accrual *from* `paused_until` once it's in the past.

This shape was chosen over a per-minute writer because the Wonder is read far more often than its HP changes, and because folding repair pauses into a single timestamp keeps the math invertible at read time.

---

## Milestones — auto-pause + explicit pay

The TODO and §14 wording is "missing a milestone pauses construction." The implementation mirrors that literally:

1. `ApplyConstruction` projects HP toward the next threshold.
2. When the threshold is crossed, HP clamps at 2,500 / 5,000 / 7,500 and `pending_milestone_percent` is set to 25 / 50 / 75.
3. Construction is paused — no further accrual — until the player calls `POST /wonder/milestone {percent}`.
4. `Wonders::PayMilestone` deducts 10%, flips the relevant `milestones_paid` flag, clears `pending_milestone_percent`, and resets `last_construction_at = now` so HP accrues from the payment moment (not from when the threshold was hit).

This was chosen over auto-deduction so the milestone is a deliberate Slack-moment for the builder.

---

## Damage path (Trebuchet → Wonder)

A Wonder lives in the kingdom's home region. The §16.3 RPS table reserves the Trebuchet/Wonder pairing at 50 HP/surviving unit, and §14 reserves Trebuchets as the primary anti-Wonder weapon (Catapults are anti-Walls).

The hook in [`Combat::Resolve`](../../app/services/combat/resolve.rb) fires **after** `ApplyOutcome` has persisted walls, loot, and army positions:

```ruby
apply_wonder_damage(battle, state, defender_kingdom, region, attacker_army)
  if outcome in %w[attacker_victory defender_rout]
  and region.id == defender_kingdom.home_region_id
  and wonder = Wonders::LiveFor.call(defender_kingdom)
  and surviving_trebuchets > 0
then Wonders::Damage.call(...)
```

`Wonders::Damage` deals `50 × surviving_trebuchets` HP, writes a [`WonderDamageEvent`](../../app/models/wonder_damage_event.rb) audit row, emits `dun.wonder.damaged`, and — if HP reaches zero — calls `Wonders::Destroy` (cancels pending phase events, status flips to `destroyed`, build queue unlocks).

A 200-Trebuchet strike one-shots a full-HP Wonder. §16.2 calibrates the Trebuchet cost so that a 200-unit force is a multi-attacker coalition investment, not a solo play.

The Wonder is **not** part of the combat State struct (the way Walls are). Walls modify defender bonus during rounds; the Wonder does not influence rounds, it just takes damage after them. Keeping it out of the simulator preserves Phase 6's surface area.

---

## Build queue lock

Per §14, the kingdom's building queue is locked while a Wonder is in progress. The lock is a single check in [`Buildings::Queue`](../../app/services/buildings/queue.rb):

```ruby
if Wonders::LiveFor.call(kingdom).present?
  raise WonderInProgress, "build queue locked: a Wonder is in progress"
end
```

Unit training continues normally (`Training::Queue` is not gated). When the Wonder is destroyed/cancelled, `LiveFor` returns nil and the queue immediately unlocks — no flag flip, no flush.

---

## Round-end hook (Phase 9 scope)

`Wonders::Complete` is the round-end critical path. In this phase it does the minimum:

1. Set the Wonder to `completed`.
2. Set the World to `archived`, populate `winner_kingdom_id` and `wonder_name`, stamp `archived_at`.
3. Emit `dun.wonder.completed` and `dun.world.archived`.

Phase 10 (Round End) will replace step 2 with a proper `Rounds::End` flow that halts in-flight marches, cancels queues, snapshots final state, recomputes leaderboards, and awards titles. Phase 9 intentionally stops short of that work — see Phase 10 in [TODO.md](../../TODO.md).

---

## Notifications

Every state-change moment emits a structured `dun.*` event (consumed by future integrations per `§17.3`):

| Event | Payload (besides `world_id`) |
|---|---|
| `dun.wonder.started` | `wonder_id`, `kingdom_id`, `name` |
| `dun.wonder.milestone_paid` | `wonder_id`, `kingdom_id`, `percent` |
| `dun.wonder.entered_consecration` | `wonder_id`, `kingdom_id`, `consecration_ends_at` |
| `dun.wonder.damaged` | `wonder_id`, `attacker_kingdom_id`, `hp_before`, `hp_after`, `damage` |
| `dun.wonder.repaired` | `wonder_id`, `kingdom_id`, `hp_repaired`, `stone_spent`, `paused_until` |
| `dun.wonder.destroyed` | `wonder_id`, `kingdom_id`, `name`, `reason` (`damage` or `cancelled`) |
| `dun.wonder.cancelled` | `wonder_id`, `kingdom_id` |
| `dun.wonder.completed` | `wonder_id`, `kingdom_id`, `name` |
| `dun.world.archived` | `winner_kingdom_id`, `wonder_name` |

---

## Cross-references

- TODO.md: Phase 9 (lines 347–382)
- GDD `§14` Wonder Mechanics (phases, identity, location, attack vectors, round-end semantics)
- GDD `§16.2` Wonder Cost Balancing (concrete cost table, HP, Trebuchet damage, repair, calibration reasoning)
- Phase 6 (Combat) — [07-combat.md](07-combat.md) — for the simulator hooks that Trebuchet damage piggybacks on
- Phase 4 (Tick) — [05-tick-engine.md](05-tick-engine.md) — for the `wonder_phase` `ScheduledEvent` kind and `dun.*` event bus
- Phase 3 (Economy) — [04-economy-and-buildings.md](04-economy-and-buildings.md) — for the `Buildings::Queue` lock check and `Stockpile::Apply` deltas pattern
