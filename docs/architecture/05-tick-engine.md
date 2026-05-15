# 05 — Tick Engine

Phase 4 of [TODO.md](../../TODO.md). The recurring jobs that drive every time-based system: build completions, training completions, march arrivals, grace expiry, production checkpoints.

The core idea: **all timed events live in one ordered table**, [scheduled_events](../../app/models/scheduled_event.rb). One recurring job drains it every 5 seconds. Phases 3/5/6/8/9 all schedule into this table; the dispatcher routes each event by `kind` to its handler.

---

## The single ordered queue

`scheduled_events` columns:

| Column | Purpose |
|---|---|
| `world_id` | every event is world-scoped |
| `kind` | one of `build_completion`, `grace_expiry`, `training_completion`, `march_arrival`, `battle_resolution`, `wonder_phase`, `caravan_arrival`, `weather_edge` |
| `payload` jsonb | handler-specific; e.g. `{ "build_order_id": "..." }` |
| `fire_at` | when the event becomes ripe |
| `processed_at` | nil until handled; non-nil = done |

Indexes:

- `(fire_at, id) WHERE processed_at IS NULL` — the hot path for the drain.
- `(world_id, kind)` — for cancel-by-payload lookups.

Why one table? Three reasons.

1. **One ordering by `fire_at` resolves all events deterministically.** No cross-table merge required.
2. **Recovery is a single query**: "find ripe events". If the worker is down for an hour, restart and drain — no special replay logic.
3. **Cancellation is a single column write** (`processed_at`). The handler dispatcher checks `event.pending?` before running, so a cancelled-then-fired event is a no-op.

---

## Recurring jobs

Solid Queue's recurring config lives at [config/recurring.yml](../../config/recurring.yml). Four jobs run on their own cadence:

| Job | Cadence | Purpose |
|---|---|---|
| [DiscreteEventTickJob](../../app/jobs/discrete_event_tick_job.rb) | every 5 seconds | drain ripe `ScheduledEvent` rows |
| [ProductionCheckpointJob](../../app/jobs/production_checkpoint_job.rb) | every 1 minute | flush stockpile accrual to disk |
| [StatsRefreshJob](../../app/jobs/stats_refresh_job.rb) | every 5 minutes | (stub; Phase 10/11 leaderboards + audit clusters) |
| [Worlds::HousekeepingJob](../../app/jobs/worlds/housekeeping_job.rb) | every hour | grace-window safety net, auto-cancel stale proposals, reap old events |

A fifth job, `clear_solid_queue_finished_jobs`, runs hourly to GC the queue itself.

The 5-second `DiscreteEventTickJob` cadence is the **tick jitter budget** from `§17.5`: ±5s drift on player-visible ETAs. ETAs are rounded to the minute on display so the jitter is invisible.

---

## The drain

[DiscreteEventTickJob](../../app/jobs/discrete_event_tick_job.rb) does one thing:

```ruby
def perform
  ScheduledEvents::Drain.call
end
```

[ScheduledEvents::Drain](../../app/services/scheduled_events/drain.rb) is the workhorse:

```ruby
def pull_batch
  ScheduledEvent.transaction do
    ScheduledEvent.ripe(now)
      .order(:fire_at, :id)
      .limit(batch_size)              # 500 by default
      .lock("FOR UPDATE SKIP LOCKED") # <-- the magic
      .to_a
  end
end
```

`FOR UPDATE SKIP LOCKED` is the safety net for two cases:

1. **Worker concurrency**: if a future deployment scales out to multiple Solid Queue workers, each tick will pull a disjoint batch.
2. **Long-running handlers**: a slow handler holds its row's lock for its entire transaction; concurrent ticks skip it instead of waiting.

The batch is processed sequentially within one tick. Each event runs through `ScheduledEvents::Dispatch` inside its own implicit transaction (the handlers all use `ActiveRecord::Base.transaction`). Failure in one event logs and continues — see [safely_dispatch](../../app/services/scheduled_events/drain.rb#L41).

Ordering: `order(:fire_at, :id)`. Two events at the same `fire_at` resolve in ULID order — deterministic, monotonic, tested.

---

## The dispatcher

[ScheduledEvents::Dispatch](../../app/services/scheduled_events/dispatch.rb) is a static map of `kind → handler lambda`:

```ruby
HANDLERS = {
  "build_completion"    => ->(e) { Buildings::Complete.call(build_order: BuildOrder.find_by(id: e.payload["build_order_id"])) },
  "grace_expiry"        => ->(e) { Worlds::EndGrace.call(e.world) },
  "training_completion" => ->(e) { Training::Complete.call(training_order: TrainingOrder.find_by(id: e.payload["training_order_id"])) },
  "march_arrival"       => ->(e) { Marches::Arrive.call(march_order: MarchOrder.find_by(id: e.payload["march_order_id"])) }
}.freeze
```

When a phase ships a new event kind, it adds an entry here. Today four kinds are wired; the other four declared in `ScheduledEvent::KINDS` (`battle_resolution`, `wonder_phase`, `caravan_arrival`, `weather_edge`) are reserved for Phases 6, 8, 9, 12.

`Dispatch` is wrapped in an `ActiveSupport::Notifications.instrument("dun.scheduled_event.processed", ...)` block — every event firing is observable on the internal bus.

### Idempotency

`event.pending?` is checked at the top of `Dispatch#call`. A processed-then-fired event is a no-op. The handler itself is expected to be idempotent too — each one early-returns on `order.resolved?` (or equivalent).

This double-guard means the system tolerates:

- A handler crashing after running its side-effect but before marking the event processed (the next tick will retry; the handler will see `resolved?` and exit).
- A canceller racing with the dispatcher (canceller wins by writing `processed_at` first; dispatcher sees `pending?` false and exits).
- Future replay/backfill scenarios.

---

## Scheduling events

[ScheduledEvents::Schedule](../../app/services/scheduled_events/schedule.rb) is the canonical write path:

```ruby
ScheduledEvents::Schedule.call(
  world: kingdom.world,
  kind: "build_completion",
  fire_at: order.completes_at,
  payload: { "build_order_id" => order.id }
)
```

It creates the row and emits `dun.scheduled_event.created`. Every service that needs a future side-effect calls this.

[ScheduledEvents::Cancel](../../app/services/scheduled_events/cancel.rb) marks an event `processed_at` without running its handler. Used by `Buildings::Cancel`, `Training::Cancel`, `Marches::Recall` to tear down a pending side-effect when its source order is cancelled.

The convention is "find-by-payload":

```ruby
event = ScheduledEvent.pending
  .where(kind: "build_completion")
  .where("payload->>'build_order_id' = ?", order.id)
  .first
ScheduledEvents::Cancel.call(event) if event
```

A bit verbose but explicit. The `(world_id, kind)` index keeps the lookup fast.

---

## Production checkpoints

[ProductionCheckpointJob](../../app/jobs/production_checkpoint_job.rb) runs every minute and calls [Stockpile::Checkpoint](../../app/services/stockpile/checkpoint.rb) on every non-eliminated kingdom in a live world:

```ruby
Kingdom
  .joins(:world)
  .where(worlds: { status: %w[grace active] })
  .where(eliminated_at: nil)
  .find_each do |kingdom|
    Stockpile::Checkpoint.call(kingdom)
  rescue => e
    Rails.logger.warn(...)
  end
```

Each kingdom is in its own transaction (via `Stockpile::Apply` underneath). A failure in one kingdom doesn't poison the rest.

Why every minute, not every tick? Two reasons:

1. **`Stockpile::Read` is always correct.** It projects forward from the checkpoint. So checkpointing is not about freshness, it's about bounding the projection arithmetic and giving the warehouse cap a chance to clamp.
2. **Write load.** Per-second checkpoints on every kingdom would be expensive. Per-minute is plenty given the projection is exact.

The job emits `dun.stockpile.checkpointed` for each kingdom processed.

---

## Housekeeping

[Worlds::HousekeepingJob](../../app/jobs/worlds/housekeeping_job.rb) runs hourly and is the **safety net** for everything that can drift:

1. **Auto-cancel stale proposed worlds** — past `auto_cancel_after_hours` (default 7 days from creation) with fewer than `min_players` joiners.
2. **Eager-start overdue proposed worlds** — any proposed world past `t0_at` that should have started but didn't (e.g. `Worlds::StartJob` was lost when the worker was down).
3. **Close overdue grace windows** — same idea for `Worlds::EndGraceJob`.
4. **Reap old processed events** — `ScheduledEvent.processed.where("processed_at < ?", 7.days.ago).delete_all`.

The housekeeping job is what makes the system resilient to worker downtime. Every "this should have happened at time T" promise has a hourly check that re-runs it if it didn't.

Future phases will add their own housekeeping concerns: weather window expiry safety, rate-limit window reset, ruin/scout cleanup. Each adds a private method to `HousekeepingJob` — see the TODO comments in `§17.5` and Phase 11.

---

## The `dun.*` event bus

`ActiveSupport::Notifications` is Rails' built-in pub-sub. dun uses it as the **internal integration seam** specified in `§17.3` of the GDD.

Every meaningful state change emits a `dun.*` notification, with the same shape: payload hash including `world_id`, the relevant entity id, and any flags an external system would want.

Today's events:

| Event | Where emitted | Payload |
|---|---|---|
| `dun.scheduled_event.created` | `ScheduledEvents::Schedule` | `event_id, world_id, kind, fire_at` |
| `dun.scheduled_event.processed` | `ScheduledEvents::Dispatch` | `event_id, world_id, kind` |
| `dun.world.grace_closed` | `Worlds::EndGrace` | `world_id, closed_at` |
| `dun.stockpile.checkpointed` | `Stockpile::Checkpoint` | `world_id, kingdom_id, checkpoint_at` |
| `dun.build_order.completed` | `Buildings::Complete` | `world_id, kingdom_id, build_order_id, building_kind, level` |
| `dun.training_order.queued` / `.completed` / `.cancelled` | `Training::Queue/Complete/Cancel` | `world_id, kingdom_id, training_order_id, unit, count, building_kind` |
| `dun.march_order.dispatched` / `.arrived` / `.recalled` | `Marches::Dispatch/Arrive/Recall` | `world_id, kingdom_id, army_id, march_order_id, intent, ...` |
| `dun.army.split` / `.merged` / `.renamed` | `Armies::Split/Merge/Rename` | `world_id, kingdom_id, army_id, ...` |

No subscriber exists in-tree today. That is on purpose: the bus is the surface for **future** integrations (Slack, webhooks, calendar invites — `§17.3`) without modifying core domain code. When a Phase 14 webhook system is built, it subscribes to `dun.*` and forwards.

If you add a state-changing service, **emit a notification**. The shape is consistent: lead with `world_id`, then the entity id, then any fields a subscriber might filter on.

---

## The lazy-vs-eager dance

The tick engine is the **eager** side. Each domain layer also has a **lazy** counterpart that resolves on read or write of a kingdom:

| Layer | Eager (tick) | Lazy (caller-pulled) |
|---|---|---|
| Builds | `DiscreteEventTickJob` → `Buildings::Complete` | [Buildings::ResolveCompletions](../../app/services/buildings/resolve_completions.rb) on every `Buildings::Queue` call |
| Training | `DiscreteEventTickJob` → `Training::Complete` | [Training::ResolveCompletions](../../app/services/training/resolve_completions.rb) on every `Training::Queue` call |
| Marches | `DiscreteEventTickJob` → `Marches::Arrive` | [Marches::ResolveArrivals](../../app/services/marches/resolve_arrivals.rb) on caller demand |
| Stockpile | `ProductionCheckpointJob` → `Stockpile::Checkpoint` | [Stockpile::Read](../../app/services/stockpile/read.rb) on every read endpoint |

Why both? Two reasons:

1. **Correctness on writes.** Between two ticks (up to 5 seconds), a write that depends on the latest state must drain its own ripe events first. Otherwise tier gates, slot counts, and `building.level` are stale.
2. **Resilience to worker downtime.** If `DiscreteEventTickJob` stops firing for an hour, players writing into the system trigger lazy catch-up. The hourly `Worlds::HousekeepingJob` is a final long-tail safety net.

Every handler is idempotent so the eager and lazy paths can race safely — see [04-economy-and-buildings.md](04-economy-and-buildings.md#the-lazy-resolve-pattern) for the full pattern.

---

## How to add a new event kind

1. Add the string to [ScheduledEvent::KINDS](../../app/models/scheduled_event.rb#L4).
2. Write a `Phase X::SomethingCompletion` service that does the work and is idempotent.
3. Register a lambda in [ScheduledEvents::Dispatch::HANDLERS](../../app/services/scheduled_events/dispatch.rb#L5).
4. Call `ScheduledEvents::Schedule.call(kind: "your_kind", ...)` from your scheduling service.
5. If your service supports cancellation, call `ScheduledEvents::Cancel` on the corresponding pending event when the source is cancelled.
6. Write a `dun.your_kind.completed` notification at the end of the handler.
7. If your service has its own lazy-resolve helper (`Phase X::ResolveCompletions`), call it eagerly at the top of every write that depends on its state.

---

## Open seams for later phases

- `wonder_phase` (Phase 9), `caravan_arrival` (Phase 8), `weather_edge` (Phase 12), `battle_resolution` (Phase 6) are all reserved kinds. None has a handler yet.
- The `StatsRefreshJob` is wired into the recurring config but its `perform` is empty — Phase 10 leaderboards and Phase 11 audit clusters will fill it in.
- No metrics are exposed on the tick yet. When Phase 14 deploys, an OpenTelemetry counter on `dun.scheduled_event.processed` is the natural insertion point (already wrapped in `instrument`).
