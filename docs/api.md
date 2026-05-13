# dun — HTTP API (v1)

Reference for every endpoint exposed by the backend at the close of Phase 1. The CLI gem and any future integration consume only this surface. Mechanics referenced as `§N.N` point at [docs/dun Game Design Document.v3.md](dun%20Game%20Design%20Document.v3.md).

## Conventions

- **Base URL.** All endpoints live under `/v1/...`. The CLI / integration should never hit any other path.
- **Format.** Request and response bodies are JSON. `Content-Type: application/json` for any body-bearing request.
- **Authentication.** Bearer ApiKey, supplied as `Authorization: Bearer <api_key>`.
  - Player keys are issued by `/v1/auth/exchange` and accepted on `/v1/...` (non-admin) routes.
  - Admin keys are issued by `/v1/admin/auth/exchange` and accepted on `/v1/admin/...` routes.
  - A player key presented at an admin endpoint, or vice versa, returns `401 unauthorized`.
- **Rolling expiry.** Each successful authenticated request slides the key's `expires_at` forward to 90 days from now and refreshes `last_used_at`. A key untouched for 90 days expires and must be re-issued via a fresh magic link.
- **Error envelope.** Every error response (4xx, 5xx) returns:
  ```json
  { "error": { "code": "string_code", "message": "human readable", "retry_after": 30 } }
  ```
  `retry_after` is present only on rate-limited responses. Documented `code` values per endpoint are listed in their respective sections.
- **Request IDs.** Every response echoes the `X-Request-Id` header (auto-generated if absent). The same ID is included in lograge JSON logs and OpenTelemetry traces.

---

## Health

### `GET /v1/health`

Liveness check. Unauthenticated.

**Response 200**
```json
{ "status": "ok" }
```

---

## Player auth — `/v1/auth/...`

### `POST /v1/auth/magic_link`

Initiates the magic-link flow for a player email. Enqueues `MagicLinkMailer#send_link` (delivered via Solid Queue). The response shape is identical whether or not a `Player` record exists for the email — no enumeration leak.

**Request**
```json
{ "email": "alice@example.com" }
```

**Response 202** — no body.

**Errors**
- `422 param_missing` — `email` not provided.

### `POST /v1/auth/exchange`

Consumes a magic-link token and issues a fresh player-scope `ApiKey`. The raw key is shown **once** in this response; only its SHA-256 digest is persisted.

On a successful exchange the service also:
1. Find-or-creates the `Player` by email (defaulting the name from the local-part).
2. Iterates every `Server` and creates `ServerMembership` + `PlayerProfile` for any whose `ServerAccess` admits the email (`§16.7` union rules).

**Request**
```json
{ "token": "<raw_magic_link_token>" }
```

**Response 201**
```json
{
  "api_key": "<raw_api_key>",
  "expires_at": "2026-08-11T07:43:00Z",
  "owner": {
    "id": 42,
    "email": "alice@example.com",
    "name": "Alice",
    "type": "player"
  }
}
```

**Errors**
- `401 invalid_token` — token unknown, or its `owner_type` is not `"Player"` (e.g. an admin token presented here).
- `401 expired` — token past its 15-minute expiry.
- `401 already_consumed` — token has been redeemed already.

### `GET /v1/auth/keys`

Lists all active and revoked keys for the current player. The key used to authenticate the request is flagged with `current: true`.

**Response 200**
```json
{
  "keys": [
    {
      "id": 7,
      "name": "laptop",
      "last_used_at": "2026-05-13T10:01:22Z",
      "expires_at": "2026-08-11T10:01:22Z",
      "revoked_at": null,
      "current": true
    },
    {
      "id": 6,
      "name": null,
      "last_used_at": "2026-04-30T09:18:01Z",
      "expires_at": "2026-07-29T09:18:01Z",
      "revoked_at": null,
      "current": false
    }
  ]
}
```

### `DELETE /v1/auth/keys/:id`

Revokes the named key (sets `revoked_at`). A revoked key 401s on subsequent use. Revoking the current key is allowed; the same response renders `204 No Content`.

**Response 204** — no body.

**Errors**
- `404 not_found` — id does not belong to the current player.

---

## Player servers — `/v1/servers/...`

### `GET /v1/servers`

Returns the union of:
1. Servers the current player is already a `ServerMembership` of (`member: true`).
2. Servers whose `ServerAccess` admits the player's email (`member: false`).

The CLI uses this for `server list`. A server appears once even if both conditions are true.

**Response 200**
```json
{
  "servers": [
    { "id": 1, "slug": "acme", "name": "Acme Co", "member": true },
    { "id": 7, "slug": "personal-friends", "name": "Friend Server", "member": false }
  ]
}
```

### `POST /v1/servers/:id/join`

Creates a `ServerMembership` if the player's email is admitted by any of the server's `ServerAccess` rules. Idempotent — a re-join returns the same `201` with the existing membership.

**Response 201**
```json
{
  "membership_id": 12,
  "server": { "id": 1, "slug": "acme", "name": "Acme Co", "member": true }
}
```

**Errors**
- `403 forbidden` — player's email is not admitted.
- `404` — server does not exist.

### `PATCH /v1/servers/:id/me`

Updates the current player's per-server profile (handle and/or real name).

The `handle` field is **case-preserved on display but case-insensitive for uniqueness within a server**. See `§17.1` for the full handle rule set:

- Length 3–20.
- Must start with a letter.
- Allowed characters: `a-zA-Z0-9_` plus single internal spaces. No leading, trailing, or consecutive spaces.
- Reserved words rejected: `admin`, `system`, `dun`, `world`, `neutral`, `wilderness`, `server`, `anonymous`, `none`, `null` (case-insensitive).

`real_name` is 1–60 chars, unicode permitted.

Either field may be omitted (no-op for the missing field). Both fields are optional in the request — at first sign-in a player will typically set both.

**Request**
```json
{ "handle": "IronFist", "real_name": "Alice Example" }
```

**Response 200**
```json
{ "handle": "IronFist", "real_name": "Alice Example", "stats": {} }
```

**Errors**
- `422 invalid` — handle or real-name violates the rules above; `message` carries the joined validation errors.
- `422 handle_locked` — handle is locked because the player is in an active round. Phase 2 activates this guard; Phase 1 returns `false` from `PlayerProfile#locked?`.
- `404` — caller has no `PlayerProfile` for this server (e.g. never admitted).

### `GET /v1/servers/:server_id/players/:handle`

Shows the per-server profile for the given handle, including the real name (only visible to server members, per `§17.1`). Caller must be a member of the server.

**Response 200**
```json
{
  "handle": "IronFist",
  "real_name": "Alice Example",
  "stats": {},
  "joined_at": "2026-05-13T10:00:00Z"
}
```

**Errors**
- `403 forbidden` — caller is not a member of the server.
- `404 not_found` — no profile with that handle on this server.

---

## Admin auth — `/v1/admin/auth/...`

Mirror of the player auth surface, scoped to `Admin` owners. Same shape, same error codes, same mailer (subject line varies).

### `POST /v1/admin/auth/magic_link`

Initiates the magic-link flow for an admin email. Enqueues `MagicLinkMailer#send_link` with `scope: "admin"`.

**Request**
```json
{ "email": "boss@example.com" }
```

**Response 202** — no body.

### `POST /v1/admin/auth/exchange`

Consumes an admin-scope token and issues a fresh admin `ApiKey`.

**Request**
```json
{ "token": "<raw_admin_magic_link_token>" }
```

**Response 201**
```json
{
  "api_key": "<raw_admin_api_key>",
  "expires_at": "2026-08-11T07:43:00Z",
  "owner": { "id": 3, "email": "boss@example.com", "name": "Boss", "type": "admin" }
}
```

**Errors**
- `401 invalid_token` — token unknown or wrong scope (e.g. a player token).
- `401 expired` — past 15 minutes.
- `401 already_consumed`.

### `GET /v1/admin/auth/keys` / `DELETE /v1/admin/auth/keys/:id`

Identical contract to the player keys endpoints, scoped to `Current.admin`.

---

## Admin servers — `/v1/admin/servers/...`

All endpoints in this section require an admin-scope ApiKey. Servers an admin does not administer (via `ServerAdminship`) are invisible — a request against an unrelated server's `:id` returns `404`.

### `GET /v1/admin/servers`

Lists every server the current admin has a `ServerAdminship` on (owner or admin role).

**Response 200**
```json
{
  "servers": [
    {
      "id": 1,
      "slug": "acme",
      "name": "Acme Co",
      "max_concurrent_worlds": 2,
      "max_worlds_per_account": 2,
      "owner_admin_id": 3
    }
  ]
}
```

### `POST /v1/admin/servers`

Creates a new server with the calling admin as owner (a `ServerAdminship(role: "owner")` is also created in the same transaction). Slug is auto-derived from the name when not provided.

**Request**
```json
{ "name": "Acme Co", "slug": "acme" }
```

`slug` is optional; constraints: 3–40 chars, lowercase letters/digits/hyphens, must start and end alphanumeric. Auto-generation lowercases the name and replaces non-alnum runs with `-`.

**Response 201**
```json
{
  "id": 1, "slug": "acme", "name": "Acme Co",
  "max_concurrent_worlds": 2, "max_worlds_per_account": 2,
  "owner_admin_id": 3
}
```

**Errors**
- `422 invalid` — slug malformed or already taken; `name` blank.

### `PATCH /v1/admin/servers/:id`

Updates the world limits and/or display name on a server the caller administers. Only the whitelist `name`, `max_concurrent_worlds`, `max_worlds_per_account` is honored — anything else (slug, owner) is silently ignored.

Per `§16.7`, limit changes apply at join time only — existing memberships are never retroactively pruned.

**Request**
```json
{ "name": "Acme Co (renamed)", "max_concurrent_worlds": 4 }
```

**Response 200** — same shape as the create response.

**Errors**
- `404` — server not administered by caller.
- `422 invalid` — values out of range (e.g. negative limit).

---

### Co-admins — `/v1/admin/servers/:server_id/admins`

`§17.1` invariant: **a server always has at least one admin**. The destroy action enforces this with a `422 last_admin` envelope.

### `GET /v1/admin/servers/:server_id/admins`

Lists all `ServerAdminship` rows on the server, ordered by `joined_at`. Includes the owner.

**Response 200**
```json
{
  "admins": [
    {
      "adminship_id": 10,
      "admin": { "id": 3, "email": "boss@example.com", "name": "Boss" },
      "role": "owner",
      "granted_by_admin_id": null,
      "joined_at": "2026-05-13T09:55:00Z"
    },
    {
      "adminship_id": 11,
      "admin": { "id": 7, "email": "coadmin@example.com", "name": "Co Admin" },
      "role": "admin",
      "granted_by_admin_id": 3,
      "joined_at": "2026-05-13T10:12:00Z"
    }
  ]
}
```

### `POST /v1/admin/servers/:server_id/admins`

Invites another email as a co-admin. Find-or-creates the `Admin` (no password needed — they sign in via `/v1/admin/auth/magic_link`). Idempotent on the (server, admin) pair.

**Request**
```json
{ "email": "coadmin@example.com" }
```

**Response 201** — same shape as one element of the index list.

### `DELETE /v1/admin/servers/:server_id/admins/:id`

`:id` is the **target Admin id** (not adminship id). Removes the adminship.

**Response 204** — no body.

**Errors**
- `404` — target admin has no adminship on this server, or caller doesn't administer the server.
- `422 last_admin` — removal would leave the server with zero admins.

---

### Invitations — `/v1/admin/servers/:server_id/invitations`

CRUD over `invite`-kind `ServerAccess` rows. Domain whitelist rows are managed elsewhere (not in Phase 1's REST surface; see "Pending" below).

### `GET /v1/admin/servers/:server_id/invitations`

Lists all invite-kind access rules, ordered by email.

**Response 200**
```json
{
  "invitations": [
    { "id": 30, "email": "guest@personal.com", "created_at": "2026-05-13T10:00:00Z" }
  ]
}
```

### `POST /v1/admin/servers/:server_id/invitations`

Adds an invite-kind access row. Idempotent on (server, email).

**Request**
```json
{ "email": "guest@personal.com" }
```

**Response 201** — same shape as a list element.

### `DELETE /v1/admin/servers/:server_id/invitations/:id`

Removes the invite row. Does NOT remove any `ServerMembership` rows the invite previously granted — admission is not retroactive per `§16.7`.

**Response 204**.

**Errors**
- `404` — id is not an invite-kind access row on this server.

---

### Members — `/v1/admin/servers/:server_id/members`

### `GET /v1/admin/servers/:server_id/members`

Lists all `ServerMembership` rows with the player's email + name (real-name field visible to admins).

**Response 200**
```json
{
  "members": [
    {
      "membership_id": 50,
      "player": { "id": 42, "email": "alice@example.com", "name": "Alice" },
      "joined_at": "2026-05-13T10:00:00Z"
    }
  ]
}
```

---

## Error reference

Codes used by Phase 1 endpoints (per-section coverage above). All shape `{"error": {"code", "message", "retry_after?"}}`.

| Code              | HTTP | Meaning |
|-------------------|------|---------|
| `unauthorized`    | 401  | Missing / invalid / wrong-scope ApiKey. |
| `invalid_token`   | 401  | Magic link token unknown or wrong owner_type. |
| `expired`         | 401  | Magic link past its 15-minute window. |
| `already_consumed`| 401  | Magic link previously redeemed. |
| `forbidden`       | 403  | Caller is not eligible (e.g. not admitted, not a member). |
| `not_found`       | 404  | Resource does not exist or is not visible to the caller. |
| `last_admin`      | 422  | Operation would leave a server with zero admins. |
| `handle_locked`   | 422  | Profile handle locked during active round (Phase 2 activates). |
| `invalid`         | 422  | Model validation failed; `message` carries joined errors. |
| `param_missing`   | 422  | Required parameter absent. |

---

## Walkthrough

End-to-end happy path that exercises the entire Phase 1 surface. Mirrors `test/integration/phase1_happy_path_test.rb`.

```sh
# 1. Bootstrap admin signs in.
curl -X POST -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com"}' \
  http://localhost:3000/v1/admin/auth/magic_link

# (Open letter_opener, copy the raw token from the email.)
ADMIN_TOKEN=...

curl -X POST -H 'Content-Type: application/json' \
  -d "{\"token\":\"$ADMIN_TOKEN\"}" \
  http://localhost:3000/v1/admin/auth/exchange
ADMIN_KEY=...   # from the response

# 2. Admin creates a server.
curl -X POST -H "Authorization: Bearer $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"name":"Acme Co"}' \
  http://localhost:3000/v1/admin/servers
SERVER_ID=...   # from the response

# 3. Admin adds a domain whitelist + an explicit invite.
#    (Domain whitelist is set directly via the model in Phase 1; only invites
#    have a REST surface. See "Pending" below.)

curl -X POST -H "Authorization: Bearer $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"email":"consultant@personal.com"}' \
  http://localhost:3000/v1/admin/servers/$SERVER_ID/invitations

# 4. Player on the domain whitelist signs in.
curl -X POST -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com"}' \
  http://localhost:3000/v1/auth/magic_link

PLAYER_TOKEN=...
curl -X POST -H 'Content-Type: application/json' \
  -d "{\"token\":\"$PLAYER_TOKEN\"}" \
  http://localhost:3000/v1/auth/exchange
PLAYER_KEY=...

# 5. Player sets handle + real name on the server.
curl -X PATCH -H "Authorization: Bearer $PLAYER_KEY" -H 'Content-Type: application/json' \
  -d '{"handle":"IronFist","real_name":"Alice Example"}' \
  http://localhost:3000/v1/servers/$SERVER_ID/me

# 6. Admin sees the member.
curl -H "Authorization: Bearer $ADMIN_KEY" \
  http://localhost:3000/v1/admin/servers/$SERVER_ID/members
```

---

## Pending (not yet exposed in v1 / Phase 1)

These endpoints / fields are referenced by the design doc or the CLI's command grammar but have not landed yet:

- **Domain whitelist REST surface.** Phase 1 only exposes invite-kind `ServerAccess` rows. Domain rules are seeded directly via model code (or future admin endpoint).
- **World endpoints** (`POST /v1/admin/servers/:id/worlds`, `GET /v1/worlds/:id`, map / regions / ruins, etc.) — Phase 2.
- **Kingdom + build + train + march endpoints** — Phases 3–5.
- **Trade ledger** (`GET /v1/worlds/:id/trade-ledger`) — Phase 8.
- **Wonder endpoints** — Phase 9.
- **Hall of fame / leaderboards** — Phase 10.
- **Reports and rate limit overrides** — Phase 11.
- **Account deletion** (`DELETE /v1/auth/account`) — Phase 10.

The route table at any point can be inspected with `bin/rails routes`.
