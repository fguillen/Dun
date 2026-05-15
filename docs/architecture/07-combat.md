# 07 — Combat Resolution & Battle Reports

Phase 6 of [TODO.md](../../TODO.md). The 6-round battle simulator (§16.3), the terrain combat layer (§16.10), Catapult-vs-Walls damage, and the Battle / BattleParticipant tables that record what happened.

Phase 5 ([06-military.md](06-military.md)) left a single integration seam at [`Marches::Arrive#handle_combat_stub`](../../app/services/marches/arrive.rb#L60). Phase 6 replaces that stub *only for intent `attack`*. The remaining stubbed intents (`capture`, `claim_ruin`) stay parked as `engaged` until Phase 7 wires node/ruin combat.

---

## What ships in this phase

| Concern | Service | Notes |
|---|---|---|
| Per-round simulator | [`Combat::Round`](../../app/services/combat/round.rb) | Pure Ruby; no DB I/O |
| Orchestrator | [`Combat::Resolve`](../../app/services/combat/resolve.rb) | Picks defender, loops 1–6 rounds, persists Battle + participants |
| Loot computation | [`Combat::ComputeLoot`](../../app/services/combat/compute_loot.rb) | min(25% of stockpile, capacity share) |
| Side-effects | [`Combat::ApplyOutcome`](../../app/services/combat/apply_outcome.rb) | Updates stockpiles, walls, army positions, destroys emptied armies |

Plus three new read endpoints (`/v1/kingdoms/:id/battles`, `/v1/battles/:id`, `/v1/admin/worlds/:id/battles`) — see [api-endpoints.md](api-endpoints.md).

---

## The 6-round simulator

[`Combat::Round.call(state, round_number:)`](../../app/services/combat/round.rb#L17) is the pure inner loop. State is a [`Combat::State`](../../app/services/combat/state.rb) struct holding both compositions, walls level / hp, terrain, RNG, and the log array.

Each round runs the same six steps both sides at once:

```
attacker_dominant = max-count unit kind on defender side
defender_dominant = max-count unit kind on attacker side

attacker_atk = Σ (count × atk × RPS[unit][attacker_dominant])   × (marsh ? 0.9 : 1.0)
defender_atk = Σ (count × atk × RPS[unit][defender_dominant])
attacker_def = Σ (count × def)
defender_def = Σ (count × def)  × (1 + min(home+walls, 0.40) + min(terrain, 0.25))

variance = uniform(0.92, 1.08)
attacker_damage = max(0, attacker_atk − defender_def × 0.5) × variance_a
defender_damage = max(0, defender_atk − attacker_def × 0.5) × variance_d

# distribute by inverse-HP weighting
defender_losses = distribute(defender_composition, attacker_damage)
attacker_losses = distribute(attacker_composition, defender_damage)
```

Inverse-HP distribution: each unit kind's weight is `count × (1 / hp[unit])`. Damage gets shared by weight, then floored to whole units killed per kind. The mechanical effect is that chaff (low HP) dies first — a 100-Levy + 100-Royal-Guard stack disproportionately loses Levies under bulk damage.

The RPS table is [`Combat::Round::RPS`](../../app/services/combat/round.rb#L8):

| Attacker | Target | Multiplier |
|---|---|---|
| knight | archer | 1.5 |
| pikeman | knight | 1.6 |
| archer | pikeman | 1.4 |

Catapult-vs-Walls is **not** a unit-vs-unit multiplier — it's a separate damage stream (see below). Royal Guard has no RPS; raw stats only.

The marsh penalty (`Region::MARSH_ATTACKER_PENALTY = −0.10`) is applied to the attacker side once, before RPS — mathematically equivalent to scaling each per-unit Atk by 0.9 before its RPS multiplier.

### Defender bonus stacking

Additive, with two independent caps from §16.3 and §16.10:

```
home_walls = 0   when defender is not at home
           = min(0.20 + 0.01 × walls_level, 0.40)   when defender is at home

terrain    = min(TERRAIN_COMBAT_MOD[region.terrain], 0.25)

defender_def_multiplier = 1.0 + home_walls + terrain
```

`TERRAIN_COMBAT_MOD` lives on [`Region`](../../app/models/region.rb#L5):

| Terrain | Defender bonus |
|---|---:|
| plains | 0.00 |
| forest | 0.10 |
| hills | 0.15 |
| mountain | 0.25 |
| marsh | 0.00 |

Marsh penalizes the attacker (Atk −10%) but gives the defender nothing. Mountain gives the defender +25% but caps the entire terrain layer at +25% — the cap exists so future terrain-stacking ideas (Phase 12 weather) cannot stack past it.

---

## Walls and Catapults

A new column `buildings.wall_hp` (nullable integer) tracks partial wall damage between battles. The convention:

- A Walls building at level L starts a fresh battle at `wall_hp = level × 1000` (see [`Building::WALL_HP_PER_LEVEL`](../../app/models/building.rb#L20)).
- Each round, surviving Catapults on the attacker side deal `120 × catapults` HP to the walls (`Combat::Round::CATAPULT_WALL_DAMAGE`).
- When `wall_hp ≤ 0`, the Walls building level drops by 1 and `wall_hp` refills to `new_level × 1000`. The defender's `defender_def_multiplier` reflects the *current* level — a wall that breaks mid-battle drops the bonus for the remaining rounds.
- Damage cascades: a 50-Catapult round can break multiple wall levels in one tick if the wall was already low.
- At level 0 there is no wall (`wall_hp = 0`, no defender bonus).

The walls building (if any) is persisted by [`Combat::ApplyOutcome#update_walls`](../../app/services/combat/apply_outcome.rb#L51) after the battle ends; the in-battle state is mutated on the in-memory `Combat::State`.

Wall damage only applies when attacking a kingdom at its home region (where the walls live). Attacks on other regions skip wall damage entirely.

---

## Defender selection

When `Marches::Arrive` calls `Combat::Resolve` for an `attack` intent, the defender side is built like this:

1. **Defender kingdom** = the kingdom whose `home_region_id == march_order.target_region_id` (and `world_id == region.world_id`), excluding the attacker. If no such kingdom exists, `Combat::Resolve` returns `nil` and `Marches::Arrive` parks the attacker as `home` at the target (no `Battle` row is created).
2. **Defender armies** = all of that kingdom's armies present at the region with `status` in `[home, engaged]`. Empty armies are filtered out.
3. **Defender aggregate** = sum of all defender army compositions, used as the combat side. After combat, casualties are redistributed back to each army by largest-contributor-first (deterministic ordering by `-count`, then `id`) — see [`Combat::Resolve#redistribute`](../../app/services/combat/resolve.rb#L189).

This Phase 6 model deliberately ignores third-party armies parked at a target that isn't their kingdom's home. They are bystanders. Wilderness regions (no home owner) get no PvP combat at all — that surface is Phase 7's domain.

---

## Rout, outcome resolution, and the log

After every round:

```
attacker_fraction = total_hp(attacker_composition) / starting_total_hp_attacker
defender_fraction = total_hp(defender_aggregate)   / starting_total_hp_defender

if attacker_fraction < 0.15  → outcome = "attacker_rout"; rout the attacker; break
if defender_fraction < 0.15  → outcome = "defender_rout"; rout the defender; break
```

A rout drops the routed side's remaining count by 30% per unit kind (floored). Battle stops early.

If neither side routs by round 6, the outcome is decided by whichever side has more surviving HP. Ties go to the defender.

| outcome | meaning |
|---|---|
| `attacker_victory` | attacker_hp > defender_hp at round 6 |
| `defender_victory` | defender_hp ≥ attacker_hp at round 6 |
| `attacker_rout` | attacker dropped below 15% HP mid-battle |
| `defender_rout` | defender dropped below 15% HP mid-battle |

The full per-round log is persisted to `battles.log` as a JSON array of `BattleRoundLogEntry` (see [openapi.yaml `BattleRoundLogEntry`](../openapi.yaml)).

---

## Loot

On attacker victory (`attacker_victory` or `defender_rout`), [`Combat::ComputeLoot`](../../app/services/combat/compute_loot.rb) computes per-resource loot as the minimum of two caps:

```
per_resource_25 = floor(defender_stockpile[resource] × 0.25)
capacity_share  = floor(attacker_surviving_total_capacity / 4)

loot[resource] = min(per_resource_25, capacity_share)
```

Capacity is divided evenly across the 4 resources (one-quarter each). This keeps the rule simple in Phase 6; future tuning can change the split if playtesting wants e.g. "raids prioritize Gold."

[`Combat::ApplyOutcome#apply_loot`](../../app/services/combat/apply_outcome.rb#L60) then:

1. Subtracts the loot from the defender's stockpile via `Stockpile::Apply`.
2. Adds it to the attacker's stockpile, *clamped by the attacker's Warehouse cap* (existing `Stockpile::Apply` semantics).
3. Records the **actual** amount the attacker received (post-cap) on `battles.loot`. If the attacker's Warehouse was already near full, the loot row in the report can be less than what came off the defender — that delta is lost to overflow.

---

## Marches::Arrive integration

```ruby
case order.intent
when "reinforce" then handle_reinforce(army, target)
when "scout"     then handle_scout(army, target)
when "attack"    then handle_attack(army, target, order)     # ← Phase 6
when "capture", "claim_ruin"
  handle_combat_stub(army, target)                            # ← Phase 7 plugs in
when "caravan"   then handle_caravan_stub(army, target)       # ← Phase 8
end
```

[`handle_attack`](../../app/services/marches/arrive.rb#L60) calls `Combat::Resolve.call(march_order: order)`. If it returns `nil` (no defender), the attacker is walked into the target as `home`. Otherwise the army's final position has already been set inside `Combat::ApplyOutcome` (`home` at target on victory, `engaged` at target on loss — or destroyed if wiped).

---

## Multi-attacker sequencing

If two attackers arrive at the same region at the same `arrives_at`, they resolve **sequentially** in ULID order. No extra code: [`ScheduledEvents::Drain`](../../app/services/scheduled_events/drain.rb#L34) already orders the ripe batch by `(fire_at, id)`, and ULIDs are monotonic by creation time.

Worked example: Wave 1 (100 Knights) and Wave 2 (100 Knights) both arrive at Carl's home (100 Pikemen) at `t = 12:00:00`. The tick at 12:00:05 drains both events in ULID order:

1. Wave 1's `Combat::Resolve` runs. Defender Pikemen lose some count, say 40. Their composition becomes 60 Pikemen.
2. Wave 2's `Combat::Resolve` runs next. It re-reads the defender state — 60 Pikemen now — and computes accordingly.

The deterministic order is asserted in [resolve_test.rb#test_second_sequential_attack_sees_casualties_from_the_first](../../test/services/combat/resolve_test.rb).

---

## Post-battle army state

| Attacker outcome | Surviving | Wiped |
|---|---|---|
| Victory | `status = home`, location = target region | army destroyed (unless Garrison) |
| Loss / rout | `status = engaged`, location = target region | army destroyed (unless Garrison) |

| Defender outcome | Surviving | Wiped |
|---|---|---|
| Any | `status = home`, location unchanged | army destroyed (unless Garrison) |

The Garrison army is never destroyed — same convention as Phase 5. Destroying an army `dependent: :destroy`s its march orders, which in turn `dependent: :nullify` the `march_order_id` on any historical `Battle` row pointing at them. `BattleParticipant.army_id` is `dependent: :nullify` for the same reason. **Battle reports always survive an army's destruction.**

---

## The `dun.*` events

Phase 6 adds two notifications, both emitted from the resolver chain:

| Event | Where | Payload |
|---|---|---|
| `dun.battle.resolved` | `Combat::Resolve` (after persisting) | `world_id, region_id, battle_id, attacker_kingdom_id, defender_kingdom_id, outcome` |
| `dun.battle.applied` | `Combat::ApplyOutcome` (after side-effects) | `world_id, battle_id, outcome, loot` |

A subscriber that just wants "a battle happened" can listen to `dun.battle.resolved`; one that needs the final loot transfer (e.g. an outbound webhook) should prefer `dun.battle.applied`.

---

## Endpoint reference

| Method | Path | Service | Visibility |
|---|---|---|---|
| GET | `/v1/kingdoms/:id/battles` | — | player owns the kingdom; ordered by `ended_at` desc; `limit` & `offset` |
| GET | `/v1/battles/:id` | — | player owns attacker or defender; returns the battle + all participants |
| GET | `/v1/admin/worlds/:id/battles` | — | any admin of the world's server |

All three are read-only — battles are written by `Combat::Resolve`, never by the HTTP surface.

---

## What this phase does not do

- **`capture` and `claim_ruin` intents** — still stubbed (`status = engaged`). Phase 7 implements `Nodes::Capture` / `Ruins::Claim` and may call `Combat::Resolve` against the wilderness garrison stored on `nodes.garrison` and `ruins.garrison`.
- **Trebuchet-vs-Wonder damage** — Wonders ship in Phase 9. Trebuchets fight units normally for now (raw 20 Atk).
- **Catapult attrition from walls** — §16.3 open follow-up. Currently surviving Catapults are unaffected by walls.
- **Scout combat behaviour** — §16.3 open follow-up (auto-flee?). Currently Scouts fight with their 2/2/4 stats; tests confirm a single Scout will likely die.
- **Async / scheduled battles** — `ScheduledEvent::KINDS` still reserves `"battle_resolution"` but Phase 6 doesn't use it (combat is synchronous inside `Marches::Arrive`). Phase 9 may use the kind for Wonder phase transitions.

---

## How to extend

Want to add a new battle outcome (e.g. `mutual_destruction`)?

1. Add to `Battle::OUTCOMES`.
2. Update `Combat::Resolve#determine_outcome` to return it.
3. Decide if attacker is treated as a winner (`Combat::ApplyOutcome::ATTACKER_WIN`) for loot purposes.
4. Update [openapi.yaml `Battle.outcome` enum](../openapi.yaml).
5. Add a controller test.

Want a new defender-side bonus (e.g. terrain × weather stack from Phase 12)?

1. Add the new modifier source to `Combat::Round#defender_def_multiplier`.
2. Keep the existing `min(terrain, 0.25)` cap or design a new one.
3. Snapshot it in the log entry so battle reports stay legible.
