# 08 — Nodes, Capture, Ruins

Phase 7 of [TODO.md](../../TODO.md). Resource Nodes and Ruins are seeded across the map at world generation (Phase 2, [03-worlds-and-maps.md](03-worlds-and-maps.md)). This phase wires what happens when a player marches an army to them: fight the static NPC garrison, take ownership of a Node, or claim a Ruin's resource cache.

Phase 6 ([07-combat.md](07-combat.md)) wired the `attack` intent in [`Marches::Arrive`](../../app/services/marches/arrive.rb). Phase 7 wires the two remaining intents — `capture` and `claim_ruin` — and exposes `GET /v1/worlds/:id/nodes` and `/nodes/:id` so clients can see what's on the map.

---

## What ships in this phase

| Concern | Service | Notes |
|---|---|---|
| Wilderness/ruin garrison combat | [`Combat::ResolveGarrison`](../../app/services/combat/resolve_garrison.rb) | reuses [`Combat::Round`](../../app/services/combat/round.rb); persists Battle with `defender_kingdom_id: nil` |
| Garrison-side effects | [`Combat::ApplyGarrisonOutcome`](../../app/services/combat/apply_garrison_outcome.rb) | casualties + army position only — no loot, walls, defender row |
| Wilderness node capture | [`Nodes::Capture`](../../app/services/nodes/capture.rb) | requires Catapult; on victory transfers ownership and clears garrison |
| Contested node attack | [`Nodes::Attack`](../../app/services/nodes/attack.rb) | PvP combat against owner's armies at the region; walks in if undefended |
| Owned-node bonuses | [`Nodes::ProductionBonus`](../../app/services/nodes/production_bonus.rb) | per-resource sum of `base_rate` across owned nodes |
| Ruin claim | [`Ruins::Claim`](../../app/services/ruins/claim.rb) | grants `ruin.cache` via `Stockpile::Apply` (warehouse-cap "excess lost") |

Plus two new read endpoints — see [api-endpoints.md](api-endpoints.md).

---

## Wilderness garrison combat

A Node or Ruin row carries a static `garrison` jsonb composition placed at map generation (e.g. `{levy: 25, archer: 10, pikeman: 5}` for a standard-tier node). When an army arrives with `capture` or `claim_ruin` intent, the attacker fights that composition.

[`Combat::ResolveGarrison.call(march_order:, garrison:, rng:)`](../../app/services/combat/resolve_garrison.rb) mirrors [`Combat::Resolve`](../../app/services/combat/resolve.rb) but:

- **No defender kingdom** — the defender row on the Battle is wilderness. The migration [`AllowWildernessBattleDefender`](../../db/migrate/20260516180000_allow_wilderness_battle_defender.rb) made `battles.defender_kingdom_id` and `battle_participants.kingdom_id` nullable so the wilderness fight can still be persisted as a Battle row and surface in `/v1/kingdoms/:id/battles` alongside PvP history.
- **No walls bonus** — `is_defender_home: false`, `walls_level: 0`, `walls_hp: 0` in the round state.
- **Terrain still applies** — both the defender's terrain-combat bonus (capped at +25%) and the marsh attacker −10% penalty are evaluated by [`Combat::Round`](../../app/services/combat/round.rb) exactly as in PvP.
- **Rout thresholds unchanged** — attacker or defender falling below 15% HP routs and absorbs an extra 30% flee.

The simulator persists a Battle with two participants: the attacker (kingdom + army populated as usual) and a wilderness defender row (`kingdom_id: nil`, `army_id: nil`, with the garrison composition in `starting_composition`). Casualties on the attacker side are applied by [`Combat::ApplyGarrisonOutcome`](../../app/services/combat/apply_garrison_outcome.rb), which is a stripped-down sibling of [`Combat::ApplyOutcome`](../../app/services/combat/apply_outcome.rb) — no loot, no walls, no defender-army updates.

A wilderness battle emits `dun.garrison.defeated` (in addition to the usual `dun.battle.applied`) carrying `{world_id, region_id, battle_id, attacker_kingdom_id, outcome}`.

---

## Node capture flow

```
army with catapult ─── march:capture ──► Marches::Arrive#handle_capture
                                            │
                                            ▼
                                  Node at target.region_id?
                                       │            │
                                     yes            no  ──► park home, emit dun.node.capture_aborted{reason:no_node}
                                       │
                                       ▼
                        node.wilderness? ────yes───► Nodes::Capture ──► ResolveGarrison ──► transfer + clear garrison
                                       │
                                       no
                                       │
                                       ▼
                                  Nodes::Attack
                                       │
                       ┌───────────────┴───────────────┐
                  defenders at region                 no defenders
                       │                                   │
                       ▼                                   ▼
              Combat::Resolve                     walk in, transfer ownership
              (defender_kingdom: owner)              (no Battle row)
```

[`Nodes::Capture`](../../app/services/nodes/capture.rb) handles wilderness nodes:

1. Validates **Catapult prerequisite** per §9 — without `catapult ≥ 1` it raises `Nodes::Capture::CatapultRequired`. The caller in [`Marches::Arrive`](../../app/services/marches/arrive.rb) rescues, parks the army `engaged`, and emits `dun.node.capture_aborted` with reason `"catapult_required"`.
2. Runs the garrison fight.
3. **On attacker victory**, transfers ownership: `node.owner_kingdom_id = army.kingdom_id`, `node.garrison = {}`. The cleared garrison is what makes "garrison defeat is one-time" per §16.5 — once defeated, no respawn.
4. **On loss / rout**, the node is unchanged. The garrison row keeps its original composition: the next attacker faces the same fresh garrison, not a partially-attrited one. (One-time defeat triggers only on a *winning* attempt.)

[`Nodes::Attack`](../../app/services/nodes/attack.rb) handles already-owned nodes:

1. Same Catapult prerequisite.
2. **If defenders are parked at the region**, run [`Combat::Resolve`](../../app/services/combat/resolve.rb) with the explicit `defender_kingdom:` kwarg — the owner is rarely homed at this region, so the resolver's default home-region lookup doesn't apply.
3. **If the region is undefended**, the attacker walks in: ownership transfers immediately with no Battle row. This matches §9's "no respawn garrison" — once cleared and unopposed, the territory is unguarded.

Both services emit `dun.node.captured` with `{world_id, region_id, node_id, kingdom_id, battle_id?}` on success. `battle_id` is `nil` for the walk-in case.

### Production bonus

[`Nodes::ProductionBonus.call(kingdom)`](../../app/services/nodes/production_bonus.rb) returns `{gold:, wood:, stone:, iron:}` summed across `kingdom.owned_nodes` by resource. It's the same sum already inlined in [`Production::RateFor`](../../app/services/production/rate_for.rb) — extracted as a service so the kingdom show endpoint can surface the node contribution alongside the building rate.

---

## Ruin claim flow

[`Ruins::Claim.call(march_order:, ruin:, rng:)`](../../app/services/ruins/claim.rb) is simpler — there's no contested path, no Catapult requirement, and the reward is a one-shot resource grant rather than persistent ownership.

1. Runs the garrison fight via [`Combat::ResolveGarrison`](../../app/services/combat/resolve_garrison.rb).
2. **On attacker victory**, applies `ruin.cache` to the attacker's kingdom via [`Stockpile::Apply`](../../app/services/stockpile/apply.rb). The cap behavior is already correct — `Stockpile::Apply` silently clamps each resource at the warehouse cap (`warehouse_cap(level) = 5_000 + 2_500 × level²`). Anything above the cap is dropped silently — that's the §16.11 "excess lost" rule, free of charge.
3. Computes the actually-granted amount (`Stockpile::Read(after) − Stockpile::Read(before)`) and writes it onto `battle.loot` so the kingdom's battle history shows what they actually walked away with.
4. Marks the ruin claimed: `claimed_by_kingdom_id`, `claimed_at`. The row is **not destroyed** — it stays visible in `GET /v1/worlds/:id/ruins` as a permanent record of who took it and when.
5. Emits `dun.ruin.claimed` with `{world_id, region_id, ruin_id, kingdom_id, battle_id, granted}`. This is the §16.11 "world announcement" — for v1 a `dun.*` event is the announcement surface; a future broadcast feature can subscribe.

---

## Home Hoard placement

Each kingdom starts with one Standard-tier Node colocated with its spawn region, marked `is_home_hoard: true`. It's placed during map generation by [`MapGeneration::PlaceSpawns#place_home_hoards`](../../app/services/map_generation/place_spawns.rb), which runs *before* the wilderness node placer ([`PlaceNodes`](../../app/services/map_generation/place_nodes.rb)).

The resource type is selected per §16.5 to "match the weakest production type at spawn." Operationally:

```ruby
counts = Kingdom::RESOURCES.index_with { 0 }
@world.nodes.where(region_id: neighbor_ids).pluck(:resource).each { |r| counts[r] += 1 }
counts.min_by { |_, c| [c, rng.rand] }.first
```

Because home hoards are placed for spawns one-by-one and the only nodes that exist at that point are the *earlier* home hoards, each subsequent spawn's home hoard biases toward whichever resource is least-represented in its neighborhood. Across a typical multi-player map this surfaces as resource diversification: rare resources for a given spawn's neighborhood get filled in first.

Home hoards inherit the standard-tier wilderness garrison (`{levy: 25, archer: 10, pikeman: 5}`). They are not owned at T0 — players must clear the garrison to take possession. This is the same one-time encounter every wilderness node has.

---

## Tick / event integration

| Trigger | Effect |
|---|---|
| `Marches::Arrive` for `capture` intent | dispatches to `Nodes::Capture` (wilderness) or `Nodes::Attack` (owned) |
| `Marches::Arrive` for `claim_ruin` intent | dispatches to `Ruins::Claim` |
| `Combat::ResolveGarrison` | persists Battle, emits `dun.garrison.defeated` |
| `Nodes::Capture` / `Nodes::Attack` on win | updates Node ownership, emits `dun.node.captured` |
| `Ruins::Claim` on win | grants cache via `Stockpile::Apply`, sets `claimed_*`, emits `dun.ruin.claimed` |

All effects happen inside the same transaction as `Marches::Arrive` — a successful arrival commits the Battle row, the ownership transfer, and the army position together, or none of them.

### `dun.*` events emitted

| Event | Payload | Fired by |
|---|---|---|
| `dun.garrison.defeated` | `world_id, region_id, battle_id, attacker_kingdom_id, outcome` | `Combat::ResolveGarrison` |
| `dun.node.captured` | `world_id, region_id, node_id, kingdom_id, battle_id?` | `Nodes::Capture`, `Nodes::Attack` |
| `dun.node.capture_aborted` | `world_id, region_id, army_id, reason` | `Marches::Arrive#handle_capture` |
| `dun.ruin.claimed` | `world_id, region_id, ruin_id, kingdom_id, battle_id, granted` | `Ruins::Claim` |
| `dun.ruin.claim_aborted` | `world_id, region_id, army_id, reason` | `Marches::Arrive#handle_claim_ruin` |

Plus the inherited `dun.battle.applied` (every wilderness battle is also a Battle row, so the existing PvP listener fires) and `dun.march_order.arrived` from the arriving march.

---

## Open follow-ups

- **Partial-attrition garrisons** — today a failed attempt leaves the wilderness garrison intact for the next attacker. The simplest reading of "garrison defeat is one-time" (§16.5) treats the encounter as a single boolean: cleared or not. If we ever want costly nibbling on a tough garrison, serialize per-attempt casualties back onto `node.garrison`.
- **Owner-stocked defender garrison** — `Nodes::Attack` currently relies on the owner sending an army to defend a captured node. Phase 13 (fog/scouting) and a possible "permanent garrison" feature could let owners stock units directly on the node row.
- **Persistent world announcements** — `dun.ruin.claimed` is the v1 announcement surface. A broadcast/notification model can subscribe and persist these for player-visible activity feeds when that work lands.
