# API Endpoint Reference

A one-page index of every endpoint currently exposed by the backend, grouped by phase and cross-linked to the architecture docs that explain each one.

The **authoritative request/response shape** is [docs/openapi.yaml](../openapi.yaml). This page is a navigation aid — endpoint names, scopes, the service each calls, the architecture chapter to read for context.

---

## Scopes

| Prefix | Scope | Auth |
|---|---|---|
| `/v1/auth/...` | Player | none required for `magic_link`/`exchange`, Bearer for the rest |
| `/v1/admin/auth/...` | Admin | same, scoped to admin |
| `/v1/servers`, `/v1/worlds`, `/v1/kingdoms`, `/v1/armies`, `/v1/battles` | Player | player-scope Bearer |
| `/v1/admin/servers`, `/v1/admin/worlds` | Admin | admin-scope Bearer |

A token from the wrong scope returns 401 — see [02-identity-and-servers.md](02-identity-and-servers.md#two-actors-one-substrate).

Errors follow `{error: {code, message, retry_after?}}` — see [01-foundations.md](01-foundations.md#error-envelope).

Every response carries `X-Request-Id`.

---

## Phase 1 — Auth, servers, profiles

See [02-identity-and-servers.md](02-identity-and-servers.md).

### Player auth

| Method | Path | Service | Notes |
|---|---|---|---|
| POST | `/v1/auth/magic_link` | `MagicLinks::Request` | sends magic link email; 15-min token |
| POST | `/v1/auth/exchange` | `MagicLinks::Consume` | redeems token → ApiKey; admits to matching servers |
| GET | `/v1/auth/keys` | — | list this player's active API keys |
| DELETE | `/v1/auth/keys/:id` | `ApiKeys::Revoke` | revoke a key |
| DELETE | `/v1/auth/account` | `Accounts::Delete` | irreversible — anonymize handles, retire for 30 days, scrub leaderboards (Phase 10) |

### Player server surface

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/servers` | — | servers admitting this player |
| POST | `/v1/servers/:id/join` | — | explicit join for invite-only servers |
| PATCH | `/v1/servers/:id/me` | `Players::SetHandle`, `Players::SetRealName` | set per-server handle / real name; handle locked during active round; retired handles unavailable for 30 days |
| GET | `/v1/servers/:server_id/players/:handle` | — | view another player's profile on this server; serializer includes inline `title` (Phase 10) |
| GET | `/v1/servers/:id/hall-of-fame` | — | four leaderboard snapshots (Champions/Wreckers/Warlords/Veterans); `?kind=` filter (Phase 10) |

### Admin auth (mirror of player auth)

| Method | Path | Service | Notes |
|---|---|---|---|
| POST | `/v1/admin/auth/magic_link` | `MagicLinks::Request` | admin-scope link |
| POST | `/v1/admin/auth/exchange` | `MagicLinks::Consume` | admin-scope ApiKey |
| GET | `/v1/admin/auth/keys` | — | list admin keys |
| DELETE | `/v1/admin/auth/keys/:id` | `ApiKeys::Revoke` | revoke admin key |

### Admin server management

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/admin/servers` | — | servers this admin administers |
| POST | `/v1/admin/servers` | `Servers::Create` | creator becomes initial admin |
| PATCH | `/v1/admin/servers/:id` | `Servers::Configure` | world limits (not retroactive) |
| DELETE | `/v1/admin/servers/:id` | `Servers::Delete` | cascades to adminships, memberships, accesses, profiles |
| GET | `/v1/admin/servers/:server_id/admins` | — | list co-admins |
| POST | `/v1/admin/servers/:server_id/admins` | `Admins::Invite` | idempotent |
| DELETE | `/v1/admin/servers/:server_id/admins/:id` | `Admins::RevokeAdminship` | guards last-admin invariant |
| GET | `/v1/admin/servers/:server_id/invitations` | — | list invite-kind access rows |
| POST | `/v1/admin/servers/:server_id/invitations` | `ServerInvitations::Create` | invite a player by email |
| DELETE | `/v1/admin/servers/:server_id/invitations/:id` | — | revoke an invite |
| GET | `/v1/admin/servers/:server_id/members` | — | list memberships (real names visible) |

---

## Phase 2 — Worlds & maps

See [03-worlds-and-maps.md](03-worlds-and-maps.md).

### Admin world management

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/admin/servers/:id/worlds` | — | list worlds on this server |
| POST | `/v1/admin/servers/:id/worlds` | `Worlds::Propose` | new proposed world; schedules `StartJob` at T0 |
| GET | `/v1/admin/worlds/:id` | — | world detail |
| PATCH | `/v1/admin/worlds/:id` | `Worlds::Configure` | edit a proposed world; re-enqueues `StartJob` if `t0_at` changes |
| POST | `/v1/admin/worlds/:id/cancel` | `Worlds::Cancel` | proposed → cancelled |
| GET | `/v1/admin/worlds/:id/invitations` | — | informational world invitations |
| POST | `/v1/admin/worlds/:id/invitations` | `WorldInvitations::Create` | informational only — admission still via ServerAccess |
| DELETE | `/v1/admin/worlds/:id/invitations/:id` | — | revoke informational invite |

### Player world surface

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/servers/:id/worlds` | — | list every world on a server you belong to (lean shape — no `my_kingdom`); 404 to non-members |
| POST | `/v1/worlds/:id/join` | `Worlds::Join` | join during proposed or grace; `AssignLateJoiner` during grace |
| GET | `/v1/worlds/:id` | — | world summary + your kingdom |
| GET | `/v1/worlds/:id/map` | — | full region/adjacency map |
| GET | `/v1/worlds/:id/regions/:region_id` | — | one region's detail |
| GET | `/v1/worlds/:id/regions/:region_id/adjacent` | — | adjacent region IDs |
| GET | `/v1/worlds/:id/ruins` | — | all ruins (claimed and unclaimed) |
| GET | `/v1/worlds/:id/archive` | — | frozen end-of-round snapshot — 404 while live (Phase 10) |

---

## Phase 3 — Economy & buildings

See [04-economy-and-buildings.md](04-economy-and-buildings.md).

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/kingdoms/:id` | `Stockpile::Read`, `Production::RateFor` | full kingdom status; lazy-projects resources |
| GET | `/v1/kingdoms/:id/build/preview?building=` | `Buildings::UpgradePreview` | next-level cost, duration, tier-gate status, affordability — read-only |
| POST | `/v1/kingdoms/:id/build` | `Buildings::Queue` | queue an upgrade; deducts via `Stockpile::Apply`, schedules `build_completion` |
| DELETE | `/v1/kingdoms/:id/build/:order_id` | `Buildings::Cancel` | 75% refund, time lost, cancels scheduled event |

---

## Phase 5 — Military

See [06-military.md](06-military.md).

### Training (kingdom-scoped)

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/kingdoms/:id/train/preview?building=&unit=&count=` | `Training::Preview` | per-unit + total cost/time, affordability, `max_affordable_count` — read-only |
| POST | `/v1/kingdoms/:id/train` | `Training::Queue` | independent queues per barracks/stable/siege_workshop |
| DELETE | `/v1/kingdoms/:id/train/:order_id` | `Training::Cancel` | 75% refund per unit count |

### Armies (army-scoped)

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/kingdoms/:id/armies` | — | list this kingdom's armies |
| GET | `/v1/armies/:id` | — | army detail + active march order |
| POST | `/v1/armies/:id/march` | `Marches::Dispatch` | plan path, schedule arrival |
| POST | `/v1/armies/:id/recall` | `Marches::Recall` | cancel arrival, schedule return |
| POST | `/v1/armies/:id/split` | `Armies::Split` | peel a new army off; both must be home |
| POST | `/v1/armies/:id/rename` | `Armies::Rename` | unique per kingdom |
| POST | `/v1/armies/:id/merge` | `Armies::Merge` | same kingdom + region + status home |

---

## Phase 6 — Combat

See [07-combat.md](07-combat.md).

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/kingdoms/:id/battles` | — | battles where this kingdom is attacker or defender; `limit`+`offset` |
| GET | `/v1/battles/:id` | — | single battle + all participants; player must own attacker or defender |
| GET | `/v1/admin/worlds/:id/battles` | — | admin-only world archive of all battles |

Wilderness battles (Phase 7) also surface here: a `Battle` row with `defender_kingdom_id: nil` represents a node capture or ruin claim.

---

## Phase 7 — Nodes, capture, ruins

See [08-nodes-and-ruins.md](08-nodes-and-ruins.md).

### Read surface

| Method | Path | Service | Notes |
|---|---|---|---|
| GET | `/v1/worlds/:id/nodes` | — | all nodes on the world: wilderness, captured, home hoards |
| GET | `/v1/worlds/:id/nodes/:id` | — | single node detail |

### Mutation paths (driven by march intents, not direct endpoints)

| Intent | Service chain | Notes |
|---|---|---|
| `capture` (wilderness) | `Marches::Arrive` → `Nodes::Capture` → `Combat::ResolveGarrison` | requires Catapult; transfers ownership on victory |
| `capture` (owned) | `Marches::Arrive` → `Nodes::Attack` → `Combat::Resolve` (or walk-in) | PvP at the node region, undefended ⇒ instant take |
| `claim_ruin` | `Marches::Arrive` → `Ruins::Claim` → `Combat::ResolveGarrison` | warehouse-capped cache grant; `dun.ruin.claimed` event |

---

## Phase 8 — Trade & caravans

See [09-trade-and-caravans.md](09-trade-and-caravans.md).

### Mutation surface

| Method | Path | Service | Notes |
|---|---|---|---|
| POST | `/v1/kingdoms/:kingdom_id/caravans` | `Caravans::Dispatch` | body: `{receiver_handle, source_army_id, payload, escort_units}` |

### Read surface

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/worlds/:world_id/trade-ledger` | paginated newest-first; filters: `?player=<handle>`, `?since=<Nh|Nd|...>`, `?limit`, `?page` |

### Mutation paths (driven by march intents, not direct endpoints)

| Intent | Service chain | Notes |
|---|---|---|
| `caravan` | `Marches::Arrive` → `Caravans::Arrive` → `Caravans::Deliver` _or_ `Caravans::Intercept` | hostile at destination ⇒ interception; otherwise delivery + scheduled return |
| `caravan_return` | `Marches::Arrive` → `Caravans::CompleteReturn` | merges escort survivors into sender's home army |

---

## Phase 9 — Wonders

See [10-wonders.md](10-wonders.md).

### Mutation surface

| Method | Path | Service | Notes |
|---|---|---|---|
| POST | `/v1/kingdoms/:kingdom_id/wonder` | `Wonders::Start` | body: `{name}` — name from §14 fixed menu |
| POST | `/v1/kingdoms/:kingdom_id/wonder/repair` | `Wonders::Repair` | body: `{hp}` — 1 HP per 8 Stone; 2000 HP/phase cap |
| POST | `/v1/kingdoms/:kingdom_id/wonder/milestone` | `Wonders::PayMilestone` | body: `{percent}` (25/50/75) |
| DELETE | `/v1/kingdoms/:kingdom_id/wonder` | `Wonders::Cancel` | abandons — paid resources lost |

### Read surface

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/kingdoms/:kingdom_id/wonder` | the kingdom's Wonder (lazy-applies construction before serializing) |
| GET | `/v1/worlds/:world_id/wonders` | public list of all Wonders in the world |

### Trigger paths (driven by combat and scheduled events, not direct endpoints)

| Trigger | Service chain | Notes |
|---|---|---|
| Attacker wins home battle, surviving Trebuchets | `Combat::Resolve` → `Wonders::Damage` (→ `Wonders::Destroy` if HP=0) | 50 HP per surviving Trebuchet |
| `wonder_phase` `enter_consecration` event (+90h) | `ScheduledEvents::Dispatch` → `Wonders::EnterConsecration` | deducts 5%, schedules `complete` at +24h |
| `wonder_phase` `complete` event (+24h consecration) | `ScheduledEvents::Dispatch` → `Wonders::Complete` | archives world, sets winner |

---

## Phase 10 — Round end, archive, leaderboards, account deletion

See [11-round-end-and-archive.md](11-round-end-and-archive.md). The three new endpoints are already listed in their natural sections above (auth, server surface, player world surface). Trigger paths driven by `Wonders::Complete` / `Wonders::Destroy` / `Combat::ApplyOutcome` (no new endpoints):

| Trigger | Service chain | Notes |
|---|---|---|
| Wonder completes (Consecration survives) | `Wonders::Complete` → `Rounds::End` → archive snapshot + stats + title + leaderboards | round freeze |
| Wonder destroyed by damage | `Wonders::Destroy` → `Wreckers::Attribute` | credits killing-blow player with `wonders_destroyed` |
| Player-vs-player battle resolved | `Combat::ApplyOutcome` → `Profiles::Increment` | raid stats (launched/defended/won, resources_looted) |
| Node ownership changes | `Nodes::Capture`/`Nodes::Attack` → `Kingdoms::BumpPeakNodes` | per-round peak rolls up at `Rounds::End` |

---

## Health

| Method | Path | Notes |
|---|---|---|
| GET | `/up` | Rails health probe (200 if app boots) |
| GET | `/v1/health` | API surface health (200, JSON `{status: "ok"}`) |

---

## What's not here

| Phase | Endpoints (planned) | Status |
|---|---|---|
| Phase 11 | `/v1/servers/:id/reports`, `/v1/admin/servers/:id/reports`, `/v1/admin/servers/:id/audit`, `/v1/admin/servers/:id/rate_limits` | not shipped |
| Phase 12 | `/v1/worlds/:id/weather` | not shipped |
| Phase 13 | `/v1/kingdoms/:id/scout`, `/v1/kingdoms/:id/scout-reports` | not shipped |

Track these in [TODO.md](../../TODO.md). When a phase ships, update this page and add a new chapter (`07-...`).
