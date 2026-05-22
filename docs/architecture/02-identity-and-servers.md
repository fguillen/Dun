# 02 — Identity & Servers

Phase 1 of [TODO.md](../../TODO.md). How players and admins sign in, how a server admits a player, and how a player ends up with a per-server profile.

The shape of this layer is unusual: **there is no password anywhere**. Auth is magic-link only, and the only persistent credential is a 90-day Bearer ApiKey. Two human roles (Player and Admin) share the same underlying tables and verbs.

---

## Two actors, one substrate

The system has two human roles:

- **Player** — plays the game from the CLI.
- **Admin** — runs a server, configures it, invites players, manages other admins.

These are separate AR models, [Player](../../app/models/player.rb) and [Admin](../../app/models/admin.rb), each carrying only `(email, name, timestamps)`. They never reference each other. A single human can be both (same email on each table) and signs in twice on the CLI — once at `/v1/auth/...` and once at `/v1/admin/auth/...`.

What they share are two **polymorphic** tables:

| Table | Owner column | Purpose |
|---|---|---|
| [magic_links](../../db/schema.rb#L100) | `owner_type` ∈ {Player, Admin}, `owner_id` | One-shot sign-in token, 15-minute expiry |
| [api_keys](../../db/schema.rb#L26) | `owner_type` ∈ {Player, Admin}, `owner_id` | Bearer credential, 90-day rolling expiry |

`owner_type` is the discriminator. A token issued for `Player` cannot authenticate an `Admin` endpoint — scope mismatch returns 401 at both consume time and request time.

---

## The auth flow

```
POST /v1/auth/magic_link              client submits email
   │
   ▼
MagicLinks::Request.call               creates MagicLink row, enqueues mailer
   │   (token_digest stored, raw token  emailed once)
   ▼
   ◄─── 202 Accepted ────────────────  (no body)

(user clicks link in email)

POST /v1/auth/exchange                 client submits raw token
   │
   ▼
MagicLinks::Consume.call
   │   - find MagicLink by token_digest
   │   - assert owner_type matches scope (Player vs Admin)
   │   - find_or_create Player by email
   │   - mark MagicLink consumed
   │   - run server admission against ServerAccess rules (Players only)
   │   - generate ApiKey
   ▼
   ◄─── 200 OK { api_key, expires_at }

(subsequent requests)

GET  /v1/...                          Authorization: Bearer <api_key>
   │
   ▼
ApiKey.authenticate(token, owner_type: "Player")
   │   - look up by token_digest
   │   - check active (not revoked, not expired)
   │   - slide expires_at forward 90d, touch last_used_at
   ▼
Current.player = api_key.owner
```

The same flow exists for admins at `/v1/admin/auth/...` with `owner_type: "Admin"`.

### MagicLink

[MagicLink](../../app/models/magic_link.rb) is single-use, 15-minute expiry. Three failure classes: `Expired`, `AlreadyConsumed`, `InvalidToken`.

- Raw tokens are 32 bytes of `SecureRandom.urlsafe_base64`.
- The DB stores only the SHA-256 digest (`MagicLink.digest`). A DB dump cannot impersonate users.
- The raw token is shown to the caller _exactly once_ — in the email body — via `MagicLinkMailer`.
- `consume!` is atomic: it asserts not-expired and not-consumed, then writes `consumed_at`.

### ApiKey

[ApiKey](../../app/models/api_key.rb) carries the persistent credential. 90-day rolling expiry: every successful `ApiKey.authenticate` call slides `expires_at` 90 days forward and refreshes `last_used_at`. The key only ages out if the user stops using it.

- `ApiKey.generate_for(owner:, name:)` is the only constructor. The raw token is returned once and never stored.
- `active` scope: `revoked_at IS NULL AND expires_at > now()`.
- `revoke!` writes `revoked_at`; subsequent auth attempts fail.
- The CLI is expected to store the raw token in OS-keychain or equivalent. The backend has no way to recover a lost key — issue a new one.

### Mailer

In development the link is opened in [letter_opener](https://github.com/ryanb/letter_opener). The production mail provider decision is deferred per `§17.1` of the GDD.

[MagicLinkMailer](../../app/mailers/magic_link_mailer.rb) gates its subject line on scope so an admin user reading their inbox sees "Your dun admin sign-in link" instead of the generic one.

---

## Servers

A **Server** is an admin-operated installation of dun. It is single-tenant by design: one server = one operator (or operator team) and a population of invited players.

[Server](../../app/models/server.rb) carries:

- `slug` — unique, lowercase URL-safe identifier (3–40 chars).
- `name` — human display name.
- `owner_admin_id` — the Admin who created the server. Always part of [ServerAdminship](../../db/schema.rb#L233) too.
- `max_concurrent_worlds` (default 2) — cap on simultaneously-live worlds.
- `max_worlds_per_account` (default 2) — cap on worlds a single player can be in.

### ServerAdminship — co-admin management

Many-to-many between admins and servers, with `role` and `granted_by_admin_id`. The **last-admin invariant** is enforced by [Admins::RevokeAdminship](../../app/services/admins/revoke_adminship.rb#L17): you cannot remove the final admin from a server. The error is `Admins::LastAdminError`.

[Admins::Invite](../../app/services/admins/invite.rb) is idempotent. Given an email it either:

- Finds an existing `Admin` by email and adds a `ServerAdminship`, _or_
- Creates the `Admin` row first (a person can be invited before they ever sign in).

### ServerAccess — who is admitted

[ServerAccess](../../app/models/server_access.rb) controls who a server admits. Two `kind` values:

- `domain` — a glob like `@example.com` or `*@example.com`. Matched as a regex against the lowercased email.
- `invite` — a literal email address.

Union semantics: a player is admitted if **any** access row matches. [ServerAccess.admits?](../../app/models/server_access.rb#L14) is the entry point; `Server#admits?(email)` is the convenience shortcut.

Admission is **not retroactive**. Changing access rules does not eject existing members; it only affects new joiners. Tested in `tests for Servers::Configure`.

[ServerInvitations::Create](../../app/services/server_invitations/create.rb) is the admin API for adding an invite-kind `ServerAccess` row. Idempotent (`find_or_create_by`).

### ServerMembership — admission, recorded

`ServerMembership` is the player-side admission record. Auto-created in two places:

1. **At magic-link consume time** — [MagicLinks::Consume#admit_to_servers](../../app/services/magic_links/consume.rb#L39) walks every server, asks `server.admits?(email)`, and creates `ServerMembership` + `PlayerProfile` rows on the first hit. This is what lets a player whose domain is allowlisted sign in once and immediately be a member of every matching server.
2. **At explicit join time** — `POST /v1/servers/:id/join` for invite-only servers, where the player has an `invite`-kind access row but has not yet been admitted.

---

## PlayerProfile — identity scoped to a server

`PlayerProfile` is the player's identity _on one server_:

| Field | Notes |
|---|---|
| `server_id`, `player_id` | unique together |
| `handle` | optional, case-insensitive unique per server (citext), reserved-word list, format `^[A-Za-z0-9_-]{3,24}$`, 3–24 chars |
| `real_name` | optional, 1–60 chars; visible to admins, hidden from other players (Phase 11 will surface admin-visible views) |
| `stats` | jsonb; filled in by Phase 10 |

The same player on two servers has two completely independent profiles — different handles, different stats. This is intentional: per-server identity is the privacy boundary.

### The locked-during-round invariant

A handle change while a round is live could break attribution (battle reports, ledger entries, leaderboards). [PlayerProfile#locked?](../../app/models/player_profile.rb#L19) returns true when the profile has any kingdom in a world whose status is `grace` or `active`:

```ruby
def locked?
  Kingdom
    .where(player_profile_id: id)
    .joins(:world)
    .where(worlds: { status: %w[grace active] })
    .exists?
end
```

[Players::SetHandle](../../app/services/players/set_handle.rb) checks `locked?` and raises `HandleLockedError` if true. Real-name changes are unrestricted ([Players::SetRealName](../../app/services/players/set_real_name.rb) — no lock).

### Reserved handles

`PlayerProfile::RESERVED_HANDLES` blocks `admin`, `system`, `dun`, `world`, `neutral`, `wilderness`, `server`, `anonymous`, `none`, `null` from being claimed.

---

## The admin endpoint surface

| Endpoint | Service | Purpose |
|---|---|---|
| `POST /v1/admin/auth/magic_link` | `MagicLinks::Request` | request admin-scope link |
| `POST /v1/admin/auth/exchange` | `MagicLinks::Consume` | redeem link → admin ApiKey |
| `GET  /v1/admin/auth/keys`, `DELETE /v1/admin/auth/keys/:id` | `ApiKeys::Revoke` | manage admin keys |
| `GET  /v1/admin/servers` | — | list servers this admin administers |
| `POST /v1/admin/servers` | `Servers::Create` | create a new server (creator = initial admin) |
| `PATCH /v1/admin/servers/:id` | `Servers::Configure` | adjust world limits |
| `DELETE /v1/admin/servers/:id` | `Servers::Delete` | hard-delete a server; cascades to adminships, memberships, accesses, profiles |
| `GET/POST/DELETE /v1/admin/servers/:server_id/admins[/:id]` | `Admins::Invite`, `Admins::RevokeAdminship` | manage co-admins (last-admin guarded) |
| `GET/POST/DELETE /v1/admin/servers/:server_id/invitations[/:id]` | `ServerInvitations::Create` | invite players by email |
| `GET  /v1/admin/servers/:server_id/members` | — | list player memberships (real names visible) |

The full request/response shapes live in [openapi.yaml](../openapi.yaml).

---

## What lives where

| Concept | Model | Service(s) | Controller(s) |
|---|---|---|---|
| Player identity | [Player](../../app/models/player.rb) | — | — |
| Admin identity | [Admin](../../app/models/admin.rb) | — | — |
| Sign-in token | [MagicLink](../../app/models/magic_link.rb) | [MagicLinks::Request](../../app/services/magic_links/request.rb), [MagicLinks::Consume](../../app/services/magic_links/consume.rb) | [Api::Auth::MagicLinksController](../../app/controllers/api/auth/magic_links_controller.rb), [Api::Admin::Auth::MagicLinksController](../../app/controllers/api/admin/auth/magic_links_controller.rb) |
| Bearer credential | [ApiKey](../../app/models/api_key.rb) | [ApiKeys::Revoke](../../app/services/api_keys/revoke.rb) | [Api::Auth::KeysController](../../app/controllers/api/auth/keys_controller.rb), [Api::Admin::Auth::KeysController](../../app/controllers/api/admin/auth/keys_controller.rb) |
| Server | [Server](../../app/models/server.rb) | [Servers::Create](../../app/services/servers/create.rb), [Servers::Configure](../../app/services/servers/configure.rb), [Servers::Delete](../../app/services/servers/delete.rb) | [Api::Admin::ServersController](../../app/controllers/api/admin/servers_controller.rb), [Api::ServersController](../../app/controllers/api/servers_controller.rb) |
| Server admission | [ServerAccess](../../app/models/server_access.rb), [ServerMembership](../../db/schema.rb#L247) | [ServerInvitations::Create](../../app/services/server_invitations/create.rb) | [Api::Admin::Servers::InvitationsController](../../app/controllers/api/admin/servers/invitations_controller.rb), [Api::Admin::Servers::MembersController](../../app/controllers/api/admin/servers/members_controller.rb) |
| Server admin grant | [ServerAdminship](../../db/schema.rb#L233) | [Admins::Invite](../../app/services/admins/invite.rb), [Admins::RevokeAdminship](../../app/services/admins/revoke_adminship.rb) | [Api::Admin::Servers::AdminsController](../../app/controllers/api/admin/servers/admins_controller.rb) |
| Per-server profile | [PlayerProfile](../../app/models/player_profile.rb) | [Players::SetHandle](../../app/services/players/set_handle.rb), [Players::SetRealName](../../app/services/players/set_real_name.rb) | [Api::Servers::MeController](../../app/controllers/api/servers/me_controller.rb), [Api::Servers::PlayersController](../../app/controllers/api/servers/players_controller.rb) |

---

## Gotchas when touching this layer

- **Scope is enforced twice.** `MagicLinks::Consume` checks that the link's `owner_type` matches the requested scope; `ApiKey.authenticate` checks that the bearer token's `owner_type` matches the scope of the endpoint. Don't try to "infer" scope from the email or the endpoint — pass it explicitly.
- **`Current.player` and `Current.admin` are mutually exclusive in a single request** but both can have values across the process if you stub auth in tests without resetting `Current`. The runner resets between requests; tests should call the auth helper.
- **The "last admin" guard is at the service layer, not the DB.** A direct `ServerAdminship.destroy_all` will happily orphan a server. Always go through `Admins::RevokeAdminship` and `Servers::Delete`.
- **PlayerProfile.handle is `citext` and unique per server.** Comparing handles in code: don't downcase in Ruby, let the DB do it.
- **Admission at consume time only loops over current servers.** If a domain rule is added _after_ a player has already consumed a link, that player will not auto-join — they have to sign in again, or the admin has to send them an invite-kind access row. This is intentional per `§16.7`.
