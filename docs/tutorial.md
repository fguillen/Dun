# Tutorial

A hands-on walkthrough of the Dun API from the perspectives of the two roles that talk to it: **Admins** (who run servers and host worlds) and **Players** (who join worlds and play the game). Each section walks through one task end-to-end with the exact requests you need.

For the full request/response contract, see [openapi.yaml](openapi.yaml). For game rules, see the [Game Design Document](dun%20Game%20Design%20Document.v3.md). For how the backend is built, see [architecture/](architecture/).

---

## 1. Before You Start

### 1.1 Prerequisites
What you need to follow along: a running Dun backend, an HTTP client (curl/httpie/Postman), an email inbox you can read magic links from.

### 1.2 Conventions used in this guide
Base URL, JSON-only responses, `Authorization: Bearer <api_key>` header, the `{ "error": { ... } }` envelope, `X-Request-Id`, and the `YYYY-MM-DD` date format.

### 1.3 Core concepts at a glance
A one-page glossary so the rest of the tutorial doesn't have to redefine: Admin vs Player, Server vs World, Kingdom, Region, Node, Army, Caravan, Wonder, Round, Archive.

---

## 2. Admin Walkthrough

The journey of someone who wants to host games for others — from zero to a running world with players in it.

### 2.1 Get authorized
Request an admin magic link, exchange the token for a 90-day Bearer API key, store it.

### 2.2 Manage your API keys
List active keys, revoke a leaked one, understand the 90-day rolling expiry.

### 2.3 Create a server
Create the top-level container that hosts worlds and players. Configure name, world limits, concurrency.

### 2.4 Configure access to the server
Two ways players get in: domain whitelist and explicit email invitations. How they combine, and why changes are not retroactive.

### 2.5 Invite co-admins
Add other admins to share operational duties. The "last admin" guard.

### 2.6 Inspect server membership
List members, view their server-scoped profiles (handle + real name), audit invitations.

### 2.7 Propose a new world
Create a world in `proposed` state: choose name, T0 start time, `min_players`, region count. Understand the auto-cancel window.

### 2.8 Edit or cancel a proposed world
Update T0, name, or `min_players` while still `proposed`. Cancel a world that won't fill.

### 2.9 World-level invitations (optional)
Send explicit per-world invites for visibility/coordination. How they differ from server-level invites.

### 2.10 Watch a world go live
World lifecycle: `proposed` → `grace` (72h late-join window) → `active` → `archived` or `cancelled`. What auto-starts, what doesn't.

### 2.11 Diagnostics while the world runs
List battles, observe combat history. What admins can and cannot see.

### 2.12 Decommissioning
Delete a server and what cascades; when not to do it.

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
