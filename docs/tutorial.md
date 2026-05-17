# Tutorial

A hands-on walkthrough of the Dun API from the perspectives of the two roles that talk to it: **Admins** (who run servers and host worlds) and **Players** (who join worlds and play the game). Each section walks through one task end-to-end with the exact requests you need.

For the full request/response contract, see [openapi.yaml](openapi.yaml). For game rules, see the [Game Design Document](dun%20Game%20Design%20Document.v3.md). For how the backend is built, see [architecture/](architecture/).

---

## 1. Before You Start

### 1.1 Prerequisites

You'll need:

- **A running Dun backend.** Locally, that's `bin/dev` from the repo root — it starts the web server on `http://localhost:3000` and the Solid Queue worker that processes jobs (mail, ticks, march arrivals). Hosted instances substitute their own base URL.
- **An HTTP client.** All examples in this guide are `curl`, but `httpie`, Postman, or your language's preferred client will do.
- **An email inbox you can read.** Magic-link tokens are mailed; you'll paste them back into the API. In development, `letter_opener` opens mailed messages in your browser instead of sending them.
- **Optional but recommended:** a JSON pretty-printer like `jq` for reading responses.

### 1.2 Conventions used in this guide

- **Base URL.** Every example below uses `http://localhost:3000/v1`. Swap in your environment's host as needed.
- **JSON in, JSON out.** Send `Content-Type: application/json` on any request with a body. Responses are always JSON, including errors.
- **Auth.** Every authenticated request carries `Authorization: Bearer <api_key>`. Player keys work only on player routes, admin keys only on admin routes — sending one to the other returns `401`.
- **Error envelope.** Failures look like `{ "error": { "code": "string_code", "message": "...", "retry_after": 30 } }`. `retry_after` appears only on rate-limit (`429`) responses.
- **Request IDs.** Every response echoes `X-Request-Id` (auto-generated if absent). The same id surfaces in lograge JSON logs and OpenTelemetry traces — quote it when reporting bugs.
- **Timestamps and dates.** All API timestamps are ISO 8601 UTC (`2026-05-17T14:30:00Z`). Dates in prose use `YYYY-MM-DD`.
- **Placeholders.** Examples use copy-paste-ready values like `k_live_abc123...` for keys and `01HK...` for IDs. Substitute the real ones from the previous step's response.

### 1.3 Core concepts at a glance

A one-page glossary; the rest of the tutorial assumes these.

- **Admin.** Runs servers, hosts worlds, configures access. Magic-link auth at `/v1/admin/auth/...`.
- **Player.** Joins worlds, plays the game. Magic-link auth at `/v1/auth/...`. A single human can be both — they sign in once on each surface.
- **Server.** Top-level tenant. Owns admins, members, and worlds. Players cannot see across server boundaries — non-members get `404`, not `403`.
- **ServerMembership.** A player's link to a server. Carries their per-server `handle` and `real_name`.
- **ServerAccess.** Admission rule: either a `domain` glob match (e.g. `*@acme.test`) or an `invite` email entry. The API surface currently exposes invite-kind rows only.
- **World.** A single round of play hosted on a server. Has a lifecycle: `proposed → grace → active → (archived | cancelled)`.
- **Round.** Synonym for a world's full lifetime from T0 to archive. Stats and Hall of Fame are per-server, summed across rounds.
- **Kingdom.** A player's instance inside one world. Holds resources, buildings, armies, and (eventually) a Wonder.
- **Region.** One tile on the world map. Has terrain, may contain nodes and ruins, and may host armies and Wonders.
- **Node.** A capturable resource-production point inside a region. Wilderness nodes have NPC garrisons; home-hoard nodes produce passively.
- **Army.** A group of units belonging to one kingdom. Lives at a region; can march, split, merge, recall.
- **Caravan.** A march with intent `caravan` — moves resources between kingdoms. Public ledger records every dispatch.
- **Wonder.** Endgame mega-build. Foundation → Construction (90h) → Consecration (24h). Surviving Consecration ends the round.
- **Archive.** Frozen, read-only snapshot of a world's final state. Created at round end.

---

## 2. Admin Walkthrough

The journey of someone who wants to host games for others — from zero to a running world with players in it.

### 2.1 Get authorized

Every admin endpoint needs an admin-scope Bearer API key. You get one by exchanging a single-use magic-link token that the backend mails to your address.

**Step 1 — Ask for the magic link.**

```bash
curl -X POST http://localhost:3000/v1/admin/auth/magic_link \
  -H 'Content-Type: application/json' \
  -d '{"email": "boss@acme.test"}'
```

`202 Accepted`, empty body. The backend enqueues `MagicLinkMailer#send_link` with `scope: "admin"`. The link is single-use and expires 15 minutes after it's mailed.

Open the email, grab the token from the link, and copy it.

**Step 2 — Exchange the token for an ApiKey.**

```bash
curl -X POST http://localhost:3000/v1/admin/auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"token": "PASTE_TOKEN_FROM_EMAIL"}'
```

`201 Created`. The fields you care about:

```json
{
  "api_key": "k_live_abc123...",
  "expires_at": "2026-08-15T10:00:00Z",
  "owner": { "type": "Admin", "...": "..." }
}
```

The `api_key` is shown **once** — the database stores only its SHA-256 digest. Copy it now; if you lose it, request a fresh magic link.

**Step 3 — Use it on every subsequent request.**

```bash
curl http://localhost:3000/v1/admin/servers \
  -H 'Authorization: Bearer k_live_abc123...'
```

Each authenticated request slides `expires_at` forward by 90 days, so an active admin's key effectively never expires — an untouched one does.

**Gotchas**
- Tokens are single-use. Re-clicking a consumed link returns `401`.
- An *admin*-scope token sent to the *player* exchange endpoint (and vice versa) returns `401`. Wrong scope = wrong endpoint.
- Missing header, expired key, or revoked key all return `401` with the standard error envelope.

See [openapi.yaml](openapi.yaml) — operations `requestAdminMagicLink` and `exchangeAdminMagicLink`.

### 2.2 Manage your API keys

Once authorized you can inspect the keys issued to you and revoke any you suspect are leaked.

**List your keys.**

```bash
curl http://localhost:3000/v1/admin/auth/keys \
  -H 'Authorization: Bearer k_live_abc123...'
```

`200 OK`:

```json
{
  "keys": [
    { "id": "01HJ...", "name": "laptop", "current": true,  "expires_at": "...", "revoked_at": null },
    { "id": "01HK...", "name": null,     "current": false, "expires_at": "...", "revoked_at": null }
  ]
}
```

Fields worth looking at: `current` (true iff this is the key you just authenticated with), `last_used_at` (to spot dormant keys), `revoked_at` (non-null means already killed).

**Revoke a key.**

```bash
curl -X DELETE http://localhost:3000/v1/admin/auth/keys/01HK... \
  -H 'Authorization: Bearer k_live_abc123...'
```

`204 No Content`. The revoked key is rejected on its next use. Revoking the key you're *currently* using is allowed — you'll just need a fresh magic link to get back in.

**The 90-day rolling window in one paragraph.** Every successful authenticated request resets that key's `expires_at` to *now + 90 days*. A key untouched for 90 days expires silently and starts returning `401` on the next call. There is no refresh-token flow: the key *is* the credential, and activity is the refresh signal.

**When to revoke vs. let expire.** Revoke if you suspect a leak — the effect is immediate. Let it expire if the key just stopped being useful (old laptop, finished automation) — no action required.

See [openapi.yaml](openapi.yaml) — operations `listAdminApiKeys` and `revokeAdminApiKey`.

### 2.3 Create a server

A server is the top-level tenant: it owns admins, members, and the worlds you'll host. Creating one in a single call makes you its owner-admin.

```bash
curl -X POST http://localhost:3000/v1/admin/servers \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{
    "name": "Acme Co",
    "slug": "acme"
  }'
```

`201 Created`:

```json
{
  "id": "01HX...",
  "slug": "acme",
  "name": "Acme Co",
  "max_concurrent_worlds": 2,
  "max_worlds_per_account": 2,
  "owner_admin_id": "01HA..."
}
```

`slug` is optional — when omitted it's auto-derived from `name`. It must match `^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$`. `max_concurrent_worlds` and `max_worlds_per_account` default to `2` each and can be tuned later.

**Update the limits.**

```bash
curl -X PATCH http://localhost:3000/v1/admin/servers/01HX... \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{ "max_concurrent_worlds": 4, "max_worlds_per_account": 2 }'
```

Whitelisted PATCH fields: `name`, `max_concurrent_worlds`, `max_worlds_per_account`. Anything else (slug, owner) is silently ignored. Per §16.7, limit changes apply **at join time only** — existing memberships are never retroactively pruned.

**List the servers you administer.**

```bash
curl http://localhost:3000/v1/admin/servers \
  -H 'Authorization: Bearer k_live_abc123...'
```

See [openapi.yaml](openapi.yaml) — `createServer`, `updateServer`, `listAdminServers`.

### 2.4 Configure access to the server

Admission is governed by `ServerAccess` rows of two kinds: `domain` glob match (e.g. `*@acme.test`) **or** `invite` (specific email). The two are unioned — a player gets in if either matches.

> **Today only the invite list is exposed via the API.** Domain glob rows live in the data model but aren't yet manageable through admin endpoints; if you need them, seed them directly. The rest of this section covers the invite list.

**Invite a player.**

```bash
curl -X POST http://localhost:3000/v1/admin/servers/01HX.../invitations \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{ "email": "guest@personal.com" }'
```

`201 Created`:

```json
{ "id": "01HV...", "email": "guest@personal.com", "created_at": "2026-05-17T10:00:00Z" }
```

Idempotent on `(server, email)` — re-inviting the same address returns the existing row.

**List or remove invitations.**

```bash
curl http://localhost:3000/v1/admin/servers/01HX.../invitations \
  -H 'Authorization: Bearer k_live_abc123...'

curl -X DELETE http://localhost:3000/v1/admin/servers/01HX.../invitations/01HV... \
  -H 'Authorization: Bearer k_live_abc123...'
```

**Admission is not retroactive (§16.7).** Removing an invitation does **not** remove any `ServerMembership` rows the invitation previously granted. To eject a member you must currently do it out-of-band. Similarly, tightening rules later won't kick existing members.

See [openapi.yaml](openapi.yaml) — `createServerInvitation`, `listServerInvitations`, `deleteServerInvitation`.

### 2.5 Invite co-admins

Once a server is yours, you can share operational duties with other admins.

**Invite a co-admin.**

```bash
curl -X POST http://localhost:3000/v1/admin/servers/01HX.../admins \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{ "email": "coadmin@example.com" }'
```

`201 Created`:

```json
{
  "adminship_id": "01HM...",
  "admin": { "id": "01HA2...", "email": "coadmin@example.com", "name": null },
  "role": "admin",
  "granted_by_admin_id": "01HA...",
  "joined_at": "2026-05-17T10:05:00Z"
}
```

The backend find-or-creates the `Admin` row — no password setup is needed. They sign in via [§2.1](#21-get-authorized) using the same magic-link flow you used. Idempotent on `(server, admin)`.

**List the current adminships.**

```bash
curl http://localhost:3000/v1/admin/servers/01HX.../admins \
  -H 'Authorization: Bearer k_live_abc123...'
```

Rows are ordered by `joined_at` and include the original owner (`role: "owner"`) alongside any co-admins (`role: "admin"`).

**Revoke a co-admin.** The path id is the **Admin id**, not the adminship id.

```bash
curl -X DELETE http://localhost:3000/v1/admin/servers/01HX.../admins/01HA2... \
  -H 'Authorization: Bearer k_live_abc123...'
```

`204 No Content`.

**The last-admin guard (§17.1).** A server must always have at least one admin. Removing the final admin returns:

```json
{ "error": { "code": "last_admin", "message": "Cannot remove the only remaining admin" } }
```

with `422`. Add a co-admin first if you want to step down.

See [openapi.yaml](openapi.yaml) — `inviteServerAdmin`, `listServerAdmins`, `revokeServerAdmin`.

### 2.6 Inspect server membership

Once players start joining, you can see who's on the server. Real names are visible to admins (§17.1).

```bash
curl http://localhost:3000/v1/admin/servers/01HX.../members \
  -H 'Authorization: Bearer k_live_abc123...'
```

`200 OK`:

```json
{
  "members": [
    {
      "membership_id": "01HN...",
      "player": { "id": "01HP...", "email": "alice@acme.test", "name": "Alice Liang" },
      "joined_at": "2026-05-17T11:00:00Z"
    }
  ]
}
```

Pair this with the invitations list ([§2.4](#24-configure-access-to-the-server)) when auditing: invitations show who you've *let in*, members show who actually *joined*.

See [openapi.yaml](openapi.yaml) — `listServerMembers`.

### 2.7 Propose a new world

A world is one round of play. You create it in `proposed` state with a future T0 (round start) and a `min_players` threshold; once both are met it auto-starts.

```bash
curl -X POST http://localhost:3000/v1/admin/servers/01HX.../worlds \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{
    "name": "Spring 2026",
    "slug": "spring-2026",
    "min_players": 4,
    "t0_at": "2026-05-24T18:00:00Z",
    "auto_cancel_after_hours": 168
  }'
```

`201 Created`:

```json
{
  "id": "01HW...",
  "server_id": "01HX...",
  "name": "Spring 2026",
  "slug": "spring-2026",
  "seed": "0x1f...",
  "status": "proposed",
  "min_players": 4,
  "auto_cancel_after_hours": 168,
  "t0_at": "2026-05-24T18:00:00Z",
  "grace_closes_at": null,
  "archived_at": null,
  "cancelled_at": null,
  "wonder_name": null
}
```

Key fields:

- `seed` is the deterministic RNG seed for map generation — same seed always produces the same map.
- `auto_cancel_after_hours` (default `168` = 7 days) caps how long a `proposed` world can sit empty before auto-cancelling.

**Concurrent world limit.** You can have at most `max_concurrent_worlds` worlds in non-terminal state per server. Exceed that and creation returns `422` with `code: "concurrent_world_limit_reached"`.

**List worlds on a server.**

```bash
curl http://localhost:3000/v1/admin/servers/01HX.../worlds \
  -H 'Authorization: Bearer k_live_abc123...'
```

Returns past and present worlds (any status).

See [openapi.yaml](openapi.yaml) — `proposeWorld`, `listAdminWorlds`.

### 2.8 Edit or cancel a proposed world

While the world is still `proposed` you can adjust `name`, `t0_at`, `min_players`, and `auto_cancel_after_hours`. Once it transitions past `proposed`, the configuration is frozen.

```bash
curl -X PATCH http://localhost:3000/v1/admin/worlds/01HW... \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{ "t0_at": "2026-05-25T18:00:00Z", "min_players": 6 }'
```

`200 OK` — returns the updated world. Changing `t0_at` reschedules the auto-start; changing `min_players` recomputes the gate at start time.

**Trying to PATCH a non-proposed world** returns `422` with `code: "world_not_configurable"`.

**Cancel a world that won't fill.**

```bash
curl -X POST http://localhost:3000/v1/admin/worlds/01HW.../cancel \
  -H 'Authorization: Bearer k_live_abc123...'
```

`200 OK` — world transitions to `cancelled` (terminal). Cancelling anything past `proposed` returns `422 world_not_cancellable`. An idle `proposed` world also self-cancels automatically `auto_cancel_after_hours` after creation.

See [openapi.yaml](openapi.yaml) — `configureWorld`, `cancelWorld`.

### 2.9 World-level invitations (optional)

`WorldInvitation` records are **informational only** — they do **not** gate join. Admission is still controlled by `ServerAccess` ([§2.4](#24-configure-access-to-the-server)). Use these for coordination and notifications when you want to flag a specific world to a player who already has server access.

```bash
curl -X POST http://localhost:3000/v1/admin/worlds/01HW.../invitations \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer k_live_abc123...' \
  -d '{ "email": "alice@acme.test" }'
```

`201 Created`:

```json
{
  "id": "01HI...",
  "email": "alice@acme.test",
  "invited_by_admin_id": "01HA...",
  "created_at": "2026-05-17T12:00:00Z"
}
```

Idempotent on duplicates. List with `GET` and remove with `DELETE` at the same path; both are no-ops on admission.

```bash
curl http://localhost:3000/v1/admin/worlds/01HW.../invitations \
  -H 'Authorization: Bearer k_live_abc123...'

curl -X DELETE http://localhost:3000/v1/admin/worlds/01HW.../invitations/01HI... \
  -H 'Authorization: Bearer k_live_abc123...'
```

See [openapi.yaml](openapi.yaml) — `createWorldInvitation`, `listWorldInvitations`, `deleteWorldInvitation`.

### 2.10 Watch a world go live

There's no `start` endpoint — worlds transition autonomously based on time and player count. The lifecycle:

1. **`proposed`** — created via [§2.7](#27-propose-a-new-world). Joinable.
2. **`grace`** — when `t0_at` is reached *and* `joined_count >= min_players`, the world auto-starts: map is generated from `seed`, spawn regions are assigned to anyone who joined during `proposed`, the 72-hour late-join window opens. `grace_closes_at` is now set.
3. **`active`** — when `grace_closes_at` passes. Late-join is closed; full game mechanics (combat, raids, Wonders) are live.
4. **`archived`** — terminal. Triggered when a Wonder survives Consecration. World is read-only; `archived_at` is set.
5. **`cancelled`** — terminal. Triggered by [§2.8](#28-edit-or-cancel-a-proposed-world) or by `auto_cancel_after_hours` elapsing while still empty.

If T0 fires but `joined_count < min_players`, the world stays `proposed` and re-checks each tick.

**Inspect current state.**

```bash
curl http://localhost:3000/v1/admin/worlds/01HW... \
  -H 'Authorization: Bearer k_live_abc123...'
```

The `status`, `t0_at`, `grace_closes_at`, `archived_at`, `cancelled_at`, and `wonder_name` fields together tell you where the round is in its arc.

See [openapi.yaml](openapi.yaml) — `showAdminWorld`.

### 2.11 Diagnostics while the world runs

The main admin observability endpoint is the per-world battle log. It surfaces every resolved fight on the server's worlds you administer.

```bash
curl 'http://localhost:3000/v1/admin/worlds/01HW.../battles?limit=25&offset=0' \
  -H 'Authorization: Bearer k_live_abc123...'
```

`200 OK`:

```json
{
  "battles": [ { "id": "01HB...", "ended_at": "...", "outcome": "...", "...": "..." } ],
  "total_count": 137
}
```

Ordered by `ended_at` desc, then `id` desc. Default `limit` is 25; max 100. Use `offset` to paginate.

**What admins can see.** Battle metadata across the world, server members and their profiles, every invitation and adminship, world configuration and seed.

**What admins cannot see.** Per-kingdom private state (resource stockpiles, build queues, march intents) is not exposed to admins — those endpoints are player-scope only. Admin observability is for hosting and moderation, not playing.

See [openapi.yaml](openapi.yaml) — `listWorldBattles`.

### 2.12 Decommissioning

When a server has outlived its purpose, you can delete it. This is destructive and cascades through every dependent row.

```bash
curl -X DELETE http://localhost:3000/v1/admin/servers/01HX... \
  -H 'Authorization: Bearer k_live_abc123...'
```

`204 No Content`. Cascades through adminships, memberships, accesses, player profiles, worlds, kingdoms, and everything those reference. Any admin on the server may delete it — no extra ownership check beyond adminship.

**When not to do this.**

- **A round is active.** Players will lose in-progress kingdoms with no archive. Wait for round end, or cancel the world first ([§2.8](#28-edit-or-cancel-a-proposed-world)).
- **You only want to slow new joins.** Reduce `max_concurrent_worlds` or stop creating worlds — deletion is a sledgehammer.
- **You only want to remove yourself.** Revoke your own adminship ([§2.5](#25-invite-co-admins)) instead, after adding a co-admin so the last-admin guard doesn't block you.

See [openapi.yaml](openapi.yaml) — `deleteServer`.

---

## 3. Player Walkthrough

The journey of someone who wants to play — from "I got an invite" to "the round is over and I'm on the leaderboard."

### 3.1 Get authorized
Request a player magic link, exchange it for a Bearer API key. First-time vs returning behavior.

### 3.2 Set up your account
Choose your per-server handle (3–20 chars, unique case-insensitive) and real name. Why these are per-server, not global.

### 3.3 Access a server
List servers you can see, join one you're admitted to (whitelist or invite).

### 3.4 Browse available worlds
Inspect a world's status, T0, grace window, region count, current participants.

### 3.5 Join a world
Create your stub kingdom by joining. What you start with: buildings L1, 500 of each resource, 20 Levy, a spawn region. The late-joiner stockpile bonus.

### 3.6 Your first steps — Economy
Read your kingdom dashboard. Queue your first building upgrade. Cancel and refund. Resource production, stockpile caps, the Warehouse.

### 3.7 Your first steps — Military
Train units at Barracks / Stable / Siege Workshop. Per-building FIFO queues. Cancel and refund. Unit roles and the rock-paper-scissors.

### 3.8 Read the map
List regions, view a region in detail, see adjacency, list nodes and ruins. The mental model of "regions hold nodes."

### 3.9 March, scout, reinforce
Inspect armies. Split and merge. Dispatch a march with the right intent. Recall in flight.

### 3.10 Capture nodes and claim ruins
Use march intents `capture` and `claim_ruin`. Wilderness garrisons. Why Catapults matter for capture.

### 3.11 Attack and raid
March `intent: attack`. Combat resolution at a glance (6 rounds, RPS, defender bonus). Read a battle report. The raid cap.

### 3.12 Trade with caravans
Dispatch a caravan with payload and escort. Delivery vs interception. Read the public trade ledger.

### 3.13 Build a Wonder
Gates to start (≥3 nodes, building requirements). Foundation → Construction → Consecration. Milestones, repairs, abandonment. Trebuchet damage and the role of defenders.

### 3.14 End of round
What happens when a Wonder consecrates: world freezes, archive is created, stats are tallied.

### 3.15 Read the archive and the Hall of Fame
Inspect the frozen final state. View per-server leaderboards: Champions, Wreckers, Warlords, Veterans.

### 3.16 Account hygiene
Rotate your API keys, delete your account, what gets anonymized vs preserved in historical records.

---

## 4. Appendix

### 4.1 Error codes you'll actually hit
The most common 4xx codes from the envelope, what they mean, and the typical fix.

### 4.2 Rate limits
Per-minute and per-hour write limits, the `429` response, `retry_after`, admin overrides.

### 4.3 Time and ticks
How discrete events, production checkpoints, and march arrivals interact with wall-clock time.

### 4.4 Further reading
Pointers back to [openapi.yaml](openapi.yaml), the [Game Design Document](dun%20Game%20Design%20Document.v3.md), and the architecture phase chapters.
