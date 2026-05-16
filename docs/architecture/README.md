# dun — Backend Architecture

This directory explains **how the dun backend is built** — the data flow, service boundaries, and lifecycle of every piece of state that the JSON API exposes.

It is _not_:

- A product description — see [PRODUCT.md](../../PRODUCT.md).
- A rules reference — see [docs/dun Game Design Document.v3.md](../dun%20Game%20Design%20Document.v3.md).
- A request/response contract — see [docs/openapi.yaml](../openapi.yaml).
- A roadmap — see [TODO.md](../../TODO.md).

The intended reader is a developer about to **change** the backend: a new feature, a bug fix, an optimization. The docs answer "what already exists, why is it shaped this way, and where do I plug in?"

---

## How to read these docs

The docs go from **outside-in**: each file zooms one level deeper.

1. **System overview** (this file) — actors, the request lifecycle, and the five concentric layers of state.
2. **Foundations** ([01-foundations.md](01-foundations.md)) — Phase 0 ground rules: the Rails 8 stack, base controllers, error envelope, ULID identifiers, observability.
3. **Identity & servers** ([02-identity-and-servers.md](02-identity-and-servers.md)) — Phase 1: how players and admins sign in, how a server admits a player, per-server profiles.
4. **Worlds & maps** ([03-worlds-and-maps.md](03-worlds-and-maps.md)) — Phase 2: world state machine, map generation pipeline, kingdom bootstrap.
5. **Economy & buildings** ([04-economy-and-buildings.md](04-economy-and-buildings.md)) — Phase 3: lazy stockpile accrual, build queue, costs and times.
6. **Tick engine** ([05-tick-engine.md](05-tick-engine.md)) — Phase 4: scheduled events, recurring jobs, the internal `dun.*` event bus.
7. **Military** ([06-military.md](06-military.md)) — Phase 5: units catalog, training, army movement.
8. **Combat** ([07-combat.md](07-combat.md)) — Phase 6: 6-round simulator, terrain combat, wall damage, battle reports.
9. **Nodes & Ruins** ([08-nodes-and-ruins.md](08-nodes-and-ruins.md)) — Phase 7: wilderness garrison combat, node capture, ruin claim, home hoards.
10. **API endpoint reference** ([api-endpoints.md](api-endpoints.md)) — every endpoint, cross-linked back to the phase that introduced it.

Phases 8–14 are not yet shipped; their slots in this doc set will fill in as the work lands.

---

## The mental model in one minute

```
Admin ──owns──> Server ──hosts──> World ──contains──> Kingdom ──owns──> Buildings, Armies, Nodes
                  ^                  ^                    ^
                  │                  │                    │
                Player ───joins via ServerAccess ──> PlayerProfile (handle, real_name, stats)
```

- A **Player** is a human who plays from the CLI client. A **Player** identity is global to the backend (one email = one Player row).
- An **Admin** is a human who operates a server. Admin identity is also global; one human can be both a Player and an Admin and signs in twice (different ApiKey scopes).
- A **Server** is an admin-operated installation (single-tenant). A Server admits players via [ServerAccess](02-identity-and-servers.md#serveraccess) rules (domain glob or invite email).
- A **PlayerProfile** is the player's identity _scoped to one server_ — handle, real name, lifetime stats. Two servers ⇒ two profiles for the same player.
- A **World** is a single round of play inside a server. A World has a finite lifecycle (proposed → grace → active → archived) and a deterministic map seeded at proposal time.
- A **Kingdom** is one player's foothold inside a World. It owns buildings, armies, and resource nodes, all of which live and die with the world.

Most domain state — Buildings, Nodes, Armies — is scoped to a Kingdom, which is scoped to a World, which is scoped to a Server. Everything above World is durable across rounds; everything below resets at round end.

---

## Request lifecycle

Every API request follows the same shape:

1. **Routing** — Rails routes mount under `/v1/...`. Player endpoints sit at the root of that namespace; admin endpoints under `/v1/admin/...`. See [config/routes.rb](../../config/routes.rb).
2. **Request ID** — [ApplicationController#set_current_request_id](../../app/controllers/application_controller.rb#L3) populates `Current.request_id` so that lograge JSON logs and OpenTelemetry traces share the same correlation token.
3. **Auth** — Player endpoints inherit [Api::BaseController](../../app/controllers/api/base_controller.rb), which runs the [Api::Authentication](../../app/controllers/concerns/api/authentication.rb) concern. Admin endpoints inherit [Api::Admin::BaseController](../../app/controllers/api/admin/base_controller.rb) and run [Api::Admin::Authentication](../../app/controllers/concerns/api/admin/authentication.rb). Both extract `Authorization: Bearer ...`, look up an `ApiKey`, refresh its sliding 90-day expiry, and populate `Current.player` or `Current.admin`. A scope mismatch (player token on admin endpoint or vice versa) returns 401.
4. **Controller** — Controllers are thin: parse params, call one service, render JSON. They do not embed business logic.
5. **Service** — Domain operations live in [app/services/](../../app/services/) under `MyNamespace::Verb` (e.g. `Buildings::Queue`). Each is `MyService.call(...)` returning a model or a result struct, or raising a domain-specific error nested under the class.
6. **Error envelope** — All errors render as `{error: {code, message, retry_after?}}` via `Api::BaseController#render_error`. `retry_after` only appears on 429 responses (Phase 11). Every response carries `X-Request-Id`.

---

## The five layers of state

The backend grows outward in five concentric rings. Each ring depends only on the rings inside it.

| Ring | Owns | Lifecycle |
|------|------|-----------|
| **Foundations** (Phase 0) | request envelope, auth substrate, observability, ULIDs | install-time |
| **Identity** (Phase 1) | Player, Admin, MagicLink, ApiKey, Server, ServerAccess, PlayerProfile | account-lifetime |
| **World** (Phase 2) | World, Region, RegionAdjacency, Node, Ruin, Kingdom | round-lifetime (~weeks) |
| **Economy, military & combat** (Phases 3, 5, 6) | Building, BuildOrder, Army, TrainingOrder, MarchOrder, Battle, BattleParticipant | kingdom-lifetime (round) |
| **Time** (Phase 4) | ScheduledEvent, recurring jobs, internal event bus | continuous |

The **Time** layer is structurally separate: it sits next to the World ring rather than inside it, because it's what gives the World state ring its evolution over time. Every dated promise (a build finishing, a march arriving) is a row in `scheduled_events`, drained every 5 seconds by the discrete-event tick job. See [05-tick-engine.md](05-tick-engine.md).

---

## What is _not_ here

- **Trade & caravans** — Phase 8.
- **Wonder mechanics, round end, anti-abuse, weather, fog of war** — Phases 9–13, none started.
- **Deployment** — Phase 14, not started. Currently `bin/dev` runs the web server and Solid Queue worker via foreman; production deployment is not yet defined.

When a phase ships, add a new section file (`07-…`, `08-…`) and link it from this README and from [api-endpoints.md](api-endpoints.md).
