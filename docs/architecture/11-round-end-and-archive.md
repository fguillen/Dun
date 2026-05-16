# 11 — Round End, Archive & Persistent Profiles

Phase 10 of [TODO.md](../../TODO.md). Implements the round-end critical path defined in `§16.6` and the persistence model in `§17.4` of the [Game Design Document](../dun%20Game%20Design%20Document.v3.md): when a Wonder survives Consecration, the round freezes instantly, the world's final state is snapshotted into a permanent archive, every participating player's lifetime stats are incremented, the winner is titled, and four per-server leaderboards are recomputed.

Phase 9 already wired Wonder completion to a stub `world.update!(status: "archived", ...)` inside [`Wonders::Complete`](../../app/services/wonders/complete.rb). Phase 10 replaces that stub with [`Rounds::End`](../../app/services/rounds/end.rb), and adds the persistence layer (stats, titles, leaderboards) plus an account-deletion path.

The freeze itself is intentionally minimal: in-flight build orders, training orders, march orders, caravans, and wonder phase transitions are **not** rewritten. Instead, [`ScheduledEvents::Dispatch`](../../app/services/scheduled_events/dispatch.rb) gains a single guard — if the event's world is `archived` or `cancelled`, the handler is skipped and `processed_at` is stamped. Live tables remain readable as last-known state inside the archive view; nothing fires.

---

## What ships in this phase

| Concern | Service / Model | Notes |
|---|---|---|
| Round-end critical path | [`Rounds::End`](../../app/services/rounds/end.rb) | Single transaction: archive, stats, title, leaderboards, notifications |
| Frozen-state snapshot | [`Rounds::SnapshotState`](../../app/services/rounds/snapshot_state.rb) | Pure projection — final regions/kingdoms/wonder/counts → JSONB |
| Atomic counter increments | [`Profiles::Increment`](../../app/services/profiles/increment.rb) | Allowlisted SQL `column = column + delta`; no row lock |
| Peak-nodes fold-in | [`Profiles::MaxPeakNodes`](../../app/services/profiles/max_peak_nodes.rb) | `peak_nodes = GREATEST(peak_nodes, candidate)` at round end |
| Per-round peak tracking | [`Kingdoms::BumpPeakNodes`](../../app/services/kingdoms/bump_peak_nodes.rb) | Recomputes on every node ownership change |
| Killing-blow attribution | [`Wreckers::Attribute`](../../app/services/wreckers/attribute.rb) | Wonders::Destroy hook; ties broken by Trebuchet count then earliest dispatch |
| Title award + render | [`Titles::Award`](../../app/services/titles/award.rb), [`Titles::Render`](../../app/services/titles/render.rb) | Idempotent award; `[Champion of <World> ×N]` rendering |
| Leaderboard recompute | [`Leaderboards::Recompute`](../../app/services/leaderboards/recompute.rb) | Four kinds, top 10, replaces snapshot row |
| Account deletion | [`Accounts::Delete`](../../app/services/accounts/delete.rb) | Tombstones player, retires handles for 30 days, scrubs leaderboards |
| 30-day handle reservation | [`Players::SetHandle`](../../app/services/players/set_handle.rb) + [`RetiredHandle`](../../app/models/retired_handle.rb) | Read-time check at handle set |
| In-flight freeze | [`ScheduledEvents::Dispatch`](../../app/services/scheduled_events/dispatch.rb) | World-archived/cancelled guard, skip-without-firing |

Plus the player surface (see [api-endpoints.md](api-endpoints.md)):

- `GET    /v1/servers/:id/hall-of-fame`
- `GET    /v1/worlds/:id/archive`
- `DELETE /v1/auth/account`

---

## Round-end flow

```
Wonders::Complete (consecration_at + 24h, HP > 0)
        │  status="completed"
        ▼
Rounds::End
        │
        ├── World.lock.find → status="archived", winner_kingdom_id, wonder_name, archived_at
        ├── Rounds::SnapshotState → JSONB → RoundArchive row
        ├── For each kingdom: Profiles::Increment(rounds_played: 1)
        │                     Profiles::MaxPeakNodes(candidate: kingdom.peak_nodes)
        ├── For the winner:  Profiles::Increment(rounds_won: 1, wonders_completed: 1)
        │                     Titles::Award(player_profile, world)
        ├── Leaderboards::Recompute(server: world.server)
        ├── dun.round.ended
        └── dun.world.archived  (kept for back-compat with Phase 9 consumers)
```

`Rounds::End` short-circuits if the world is already archived — re-entrant safe under double-fire.

The freeze itself is structurally lazy: nothing in `build_orders`, `training_orders`, `march_orders`, `caravans`, or `wonders` is rewritten. The `ScheduledEvents::Dispatch` guard ensures their ripe events become no-ops once the world flips. Read endpoints (kingdom show, army show, etc.) continue to return whatever was in those tables at the freeze moment.

---

## Persistent player stats (§17.4)

Stats live on a dedicated `player_profile_stats` row (1:1 with `player_profile`), created by an `after_create` hook on `PlayerProfile` so every profile always has its stats row. The 10 counters and where they bump:

| Counter | Bumped by | When |
|---|---|---|
| `rounds_played` | [`Rounds::End`](../../app/services/rounds/end.rb) | once per kingdom in the world at round end |
| `rounds_won` | `Rounds::End` | for the winning kingdom's player |
| `wonders_completed` | `Rounds::End` | same moment as `rounds_won` |
| `wonders_destroyed` | [`Wreckers::Attribute`](../../app/services/wreckers/attribute.rb) (called from [`Wonders::Destroy`](../../app/services/wonders/destroy.rb)) | only when `reason: "damage"` (not on voluntary `Wonders::Cancel`) |
| `peak_nodes` | `Profiles::MaxPeakNodes` at `Rounds::End` | folds this-round `Kingdom.peak_nodes` into the lifetime max |
| `raids_launched` | [`Combat::ApplyOutcome`](../../app/services/combat/apply_outcome.rb) | every player-vs-player battle resolution (attacker side) |
| `raids_defended` | `Combat::ApplyOutcome` | same battles, defender side |
| `raids_won_offense` | `Combat::ApplyOutcome` | attacker side when `outcome ∈ {attacker_victory, defender_rout}` |
| `raids_won_defense` | `Combat::ApplyOutcome` | defender side otherwise (only when both sides are player kingdoms) |
| `resources_looted` | `Combat::ApplyOutcome` | sum of looted resources on attacker win |

Wilderness garrison combat and caravan escort combat are *not* counted as raids — both bypass `Combat::ApplyOutcome` (the former has no defender kingdom; the latter routes through `Combat::ApplyEscortOutcome`). This matches §17.4's "incoming attacks resolved at the player's regions" wording.

`Profiles::Increment` uses a single allowlisted UPDATE so concurrent increments compose without row-level locking:

```sql
UPDATE player_profile_stats SET rounds_played = rounds_played + 1, raids_launched = raids_launched + 3 ...
```

The column names are gated by `PlayerProfileStats::COUNTER_COLUMNS`. Unknown columns raise `Profiles::Increment::UnknownColumn`.

---

## Wrecker attribution

`Wonders::Destroy` calls `Wreckers::Attribute` only when `reason == "damage"`. Cancellations (voluntary `Wonders::Cancel`) credit no one.

`Wreckers::Attribute` picks the `WonderDamageEvent` whose `hp_after == 0` — the row that brought the Wonder's HP to zero. §17.4 tiebreakers:

```sql
WHERE wonder_id = ? AND hp_after = 0
ORDER BY trebuchets_surviving DESC, occurred_at ASC
LIMIT 1
```

In normal play only one damage event hits `hp_after = 0` because the damage stream is sequential through the tick engine. The tiebreakers are defensive — they cover the (rare) case where multiple battles at the same `fire_at` both end the Wonder.

---

## Titles

`PlayerTitle (player_profile_id, world_id, kind, awarded_at)` is a thin row. `Titles::Award` is idempotent (`find_or_create_by` on the natural key).

`Titles::Render.call(profile)` is the inline string used by every player-facing serializer:

1. Pick the player's most recent champion title (by `awarded_at`).
2. Count champion titles for that title's *world name* (not world id).
3. Format: `[Champion of <World> ×N]` (the `×N` is omitted when N=1, per the GDD example).

Repeat wins on the same world name collapse into `×N`; repeat wins across different worlds show only the most recent inline, and the rest are available via the player's profile page.

---

## Leaderboards

Per §17.4, four leaderboards per server, **recomputed only at round end** and snapshotted into `leaderboard_snapshots` (one row per `(server_id, kind)`):

| Kind | Sort |
|---|---|
| Champions | `rounds_won DESC, wonders_destroyed DESC` |
| Wreckers | `wonders_destroyed DESC, rounds_won DESC` |
| Warlords | `peak_nodes DESC, rounds_won DESC` |
| Veterans | `rounds_played DESC, rounds_won DESC` |

Each snapshot stores top 10 entries as a JSONB array: `{player_profile_id, handle, score, secondary}`. Entries with zero in the primary column are filtered out.

The snapshot row replaces (not appends to) any previous snapshot for the same `(server_id, kind)` — once the round ends, the new picture overwrites the old.

`GET /v1/servers/:id/hall-of-fame` returns all four envelopes; `?kind=champions` filters to one. The serializer joins each entry back to its current `PlayerProfile` for inline title rendering, so a player who won a *later* round appears with the latest title on every leaderboard.

---

## Archive

`RoundArchive (world_id [unique], winner_kingdom_id, wonder_name, frozen_state jsonb, ended_at)`. `frozen_state` is built by `Rounds::SnapshotState` and is **opaque to the API** — it is never queried into, only served whole by `GET /v1/worlds/:id/archive`.

The shape (documented in [`docs/openapi.yaml`](../openapi.yaml) `FrozenState`):

- `ended_at`: ISO-8601
- `regions[]`: id, name, terrain, position, is_hub, node_ids
- `kingdoms[]`: id, handle, real_name, home_region_id, final_stockpiles, building_levels, peak_nodes, final_node_count, joined_at, eliminated_at
- `wonder`: kingdom_id, name, status, hp, target_hp, damage_events_count, started_at, completed_at, destroyed_at (nullable)
- `battles_count`, `caravans_count`, `nodes_count`

Why a single JSONB blob instead of per-table snapshot mirrors? The archive is read-only and aggregate. There is no use case (yet) that queries inside it. A per-table mirror would add ten migration tables and ten ETL transactions inside the round-end transaction without paying for itself.

---

## Account deletion

`DELETE /v1/auth/account` invokes [`Accounts::Delete`](../../app/services/accounts/delete.rb) on the calling player. The flow is irreversible and bundles every operation into one transaction:

1. **Per profile** (one for each server the player belongs to):
   - Insert a `RetiredHandle (server_id, handle_lower, freed_at)` if the handle was set.
   - Anonymize the profile via `update_columns(handle: "[deleted player ##{id}]", real_name: nil)` (the placeholder uses brackets that the handle format regex rejects, hence `update_columns` to skip validation; the DB index is citext-unique by construction).
   - Zero every counter in `PlayerProfileStats` via a single SQL UPDATE.
   - Delete the player's `PlayerTitle` rows.
2. **Server-wide**: scrub the player's `player_profile_id` from every `LeaderboardSnapshot.entries` jsonb array.
3. **Player row**: stamp `deleted_at`, tombstone `email = "deleted-<id>@dun.local"`, `name = "[deleted]"`. The row stays so battle reports and ledger entries that reference its profiles remain joinable.
4. **ApiKeys**: every active `ApiKey` for the player is revoked (`revoked_at = now`). The caller's own key becomes invalid immediately — the next request returns 401.
5. Emit `dun.account.deleted`.

The 30-day reservation is *read-time*: `Players::SetHandle` consults `RetiredHandle.reserved?` (`freed_at > now - 30.days`) and raises `Players::SetHandle::HandleReservedError` if the requested handle is still locked.

Re-signup via magic link uses email as the primary identifier. After tombstoning, the deleted player's original email no longer matches any non-deleted Player row, so `MagicLinks::Consume` creates a fresh `Player`. Battle reports, ledger entries, and archives keep their `*_handle_at_send`-style snapshots intact; live profile rows display `[deleted player #...]`.

---

## In-flight freeze

The only structural change in the tick engine is one guard in [`ScheduledEvents::Dispatch`](../../app/services/scheduled_events/dispatch.rb):

```ruby
if world_frozen?
  @event.update!(processed_at: Time.current)
  ActiveSupport::Notifications.instrument("dun.scheduled_event.skipped_world_archived", ...)
  return @event
end
```

`world_frozen?` checks `world.archived? || world.cancelled?`. The handler never runs; the event is marked processed so the drain stops pulling it. Build orders, training orders, march orders, and caravans on an archived world remain in their last-known state — they simply never resolve.

This was chosen over an eager iterate-and-cancel pass because:
- The eager pass would require touching five tables in the round-end transaction, increasing lock contention and migration risk for no functional gain.
- `§16.6` is explicit: the world enters *read-only* archive mode. The current in-flight state is part of what gets preserved; the archive snapshot reads it as-is.
- Defense-in-depth would be cheap to add later (one more `update_all` in `Rounds::End`) without rewiring anything.

---

## `dun.*` events emitted

| Event | Payload (besides `world_id`) | When |
|---|---|---|
| `dun.round.ended` | `winner_kingdom_id`, `wonder_name` | inside `Rounds::End` |
| `dun.world.archived` | `winner_kingdom_id`, `wonder_name` | kept for back-compat with Phase 9 consumers |
| `dun.account.deleted` | `player_id` | inside `Accounts::Delete` |
| `dun.scheduled_event.skipped_world_archived` | `event_id`, `kind` | freezing guard fires |

---

## Cross-references

- TODO.md: Phase 10 (lines 389–417)
- GDD `§16.6` Round-Over and Reset (freeze semantics, archive contents)
- GDD `§17.4` Persistence Model (stats taxonomy, title format, leaderboard rules, account deletion)
- Phase 9 (Wonders) — [10-wonders.md](10-wonders.md) — for the `Wonders::Complete` → `Rounds::End` handoff
- Phase 6 (Combat) — [07-combat.md](07-combat.md) — for the raid-stat hook in `Combat::ApplyOutcome`
- Phase 7 (Nodes) — [08-nodes-and-ruins.md](08-nodes-and-ruins.md) — for the `Kingdoms::BumpPeakNodes` callsite
- Phase 4 (Tick) — [05-tick-engine.md](05-tick-engine.md) — for the dispatcher freeze guard
