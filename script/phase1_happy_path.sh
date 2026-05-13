#!/usr/bin/env bash
#
# Replays the Phase 1 happy-path end-to-end against a running dev server
# using only curl. Mirrors test/integration/phase1_happy_path_test.rb with
# one deviation: Alice is invited explicitly instead of joining via the
# `*@example.com` domain whitelist, because Phase 1 exposes no HTTP endpoint
# for domain-kind ServerAccess. Both players therefore enter via invitations.
#
# Usage:
#   bin/dev                                # in another terminal
#   rm -rf tmp/letter_opener/*             # optional, makes "latest mail" unambiguous
#   bin/rails db:reset && bin/rails db:seed
#   script/phase1_happy_path.sh
#
# At each magic-link step the script pauses and prints the most recent
# letter_opener mail directory; open it, copy the raw token, paste, hit Enter.
#
# Requires: curl, jq, a running Rails server on $BASE_URL.

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
ADMIN_BOOTSTRAP_EMAIL="${ADMIN_BOOTSTRAP_EMAIL:-admin@example.com}"
MAIL_DIR="tmp/letter_opener"

banner() { printf '\n===> %s\n' "$*"; }
fail()   { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

# req METHOD PATH [JSON_BODY] [BEARER_TOKEN] [EXPECTED_STATUS]
# Echoes the response body on stdout. Status validation is mandatory.
req() {
  local method="$1" path="$2" body="${3:-}" bearer="${4:-}" expected="${5:-}"
  local url="${BASE_URL}${path}"
  local args=(-sS -X "$method" -H 'Accept: application/json' -w $'\n%{http_code}' "$url")
  [[ -n "$body"   ]] && args+=(-H 'Content-Type: application/json' --data-raw "$body")
  [[ -n "$bearer" ]] && args+=(-H "Authorization: Bearer ${bearer}")

  printf '    $ curl' >&2
  printf ' %q' "${args[@]}" >&2
  printf '\n' >&2

  local raw status response
  raw=$(curl "${args[@]}")
  status=$(printf '%s' "$raw" | tail -n1)
  response=$(printf '%s' "$raw" | sed '$d')

  printf '    -> %s %s  %s\n' "$method" "$path" "$status" >&2
  if [[ -n "$response" ]]; then
    if ! printf '%s' "$response" | jq --indent 2 . >&2 2>/dev/null; then
      printf '%s\n' "$response" >&2
    fi
  fi
  if [[ -n "$expected" && "$status" != "$expected" ]]; then
    fail "expected $expected, got $status for $method $path"
  fi
  printf '%s' "$response"
}

# Pause for the operator to paste a raw magic-link token.
prompt_token() {
  local email="$1" scope="$2" token=""
  {
    echo
    echo "    Magic link sent to: $email  (scope: $scope)"
    if [[ -d "$MAIL_DIR" ]]; then
      local latest
      latest=$(ls -td "$MAIL_DIR"/*/ 2>/dev/null | head -1 || true)
      if [[ -n "$latest" ]]; then
        echo "    Latest mail dir:    $latest"
        local plain="${latest}plain.html"
        if [[ -f "$plain" ]]; then
          local hint
          hint=$(grep -oE '[A-Za-z0-9_-]{20,}' "$plain" | head -1 || true)
          [[ -n "$hint" ]] && echo "    Token candidate:    $hint"
        fi
      fi
    fi
    printf '    Paste token and press Enter: '
  } >&2
  read -r token
  [[ -n "$token" ]] || fail "empty token"
  printf '%s' "$token"
}

# -------------------------------------------------------------------------
# 1. Bootstrap admin must exist (seeded by `bin/rails db:seed`).
# -------------------------------------------------------------------------
banner "Step 1: confirm bootstrap admin exists ($ADMIN_BOOTSTRAP_EMAIL)"
echo "    (run \`bin/rails db:seed\` first if this is a fresh DB)"

# -------------------------------------------------------------------------
# 2-4. Bootstrap admin signs in.
# -------------------------------------------------------------------------
banner "Step 2: POST /v1/admin/auth/magic_link  (bootstrap admin)"
req POST /v1/admin/auth/magic_link \
  "$(jq -nc --arg e "$ADMIN_BOOTSTRAP_EMAIL" '{email:$e}')" \
  "" 202 >/dev/null

banner "Step 3: operator pastes admin magic-link token"
ADMIN_TOKEN=$(prompt_token "$ADMIN_BOOTSTRAP_EMAIL" admin)

banner "Step 4: POST /v1/admin/auth/exchange"
resp=$(req POST /v1/admin/auth/exchange \
  "$(jq -nc --arg t "$ADMIN_TOKEN" '{token:$t}')" "" 201)
ADMIN_API_KEY=$(printf '%s' "$resp" | jq -r '.api_key')
echo "    admin_api_key = $ADMIN_API_KEY"

# -------------------------------------------------------------------------
# 5. Admin creates a server.
# -------------------------------------------------------------------------
banner "Step 5: POST /v1/admin/servers  (create \"Acme Co\")"
resp=$(req POST /v1/admin/servers '{"name":"Acme Co"}' "$ADMIN_API_KEY" 201)
SERVER_ID=$(printf '%s' "$resp" | jq -r '.id')
echo "    server_id = $SERVER_ID"

# -------------------------------------------------------------------------
# 6-7. Invite both players.
# -------------------------------------------------------------------------
banner "Step 6: invite Alice  (replaces the domain-whitelist branch)"
req POST "/v1/admin/servers/${SERVER_ID}/invitations" \
  '{"email":"alice@example.com"}' "$ADMIN_API_KEY" 201 >/dev/null

banner "Step 7: invite Bob"
req POST "/v1/admin/servers/${SERVER_ID}/invitations" \
  '{"email":"consultant@personal.com"}' "$ADMIN_API_KEY" 201 >/dev/null

# -------------------------------------------------------------------------
# 8-9. Alice signs in and sets her profile.
# -------------------------------------------------------------------------
banner "Step 8: Alice POST /v1/auth/magic_link + exchange"
req POST /v1/auth/magic_link '{"email":"alice@example.com"}' "" 202 >/dev/null
ALICE_TOKEN=$(prompt_token alice@example.com player)
resp=$(req POST /v1/auth/exchange \
  "$(jq -nc --arg t "$ALICE_TOKEN" '{token:$t}')" "" 201)
ALICE_API_KEY=$(printf '%s' "$resp" | jq -r '.api_key')
echo "    alice_api_key = $ALICE_API_KEY"

banner "Step 9: PATCH /v1/servers/${SERVER_ID}/me  (Alice profile)"
req PATCH "/v1/servers/${SERVER_ID}/me" \
  '{"handle":"AliceTheBold","real_name":"Alice Example"}' \
  "$ALICE_API_KEY" 200 >/dev/null

# -------------------------------------------------------------------------
# 10-11. Bob signs in and sets his profile.
# -------------------------------------------------------------------------
banner "Step 10: Bob POST /v1/auth/magic_link + exchange"
req POST /v1/auth/magic_link '{"email":"consultant@personal.com"}' "" 202 >/dev/null
BOB_TOKEN=$(prompt_token consultant@personal.com player)
resp=$(req POST /v1/auth/exchange \
  "$(jq -nc --arg t "$BOB_TOKEN" '{token:$t}')" "" 201)
BOB_API_KEY=$(printf '%s' "$resp" | jq -r '.api_key')
echo "    bob_api_key = $BOB_API_KEY"

banner "Step 11: PATCH /v1/servers/${SERVER_ID}/me  (Bob profile)"
req PATCH "/v1/servers/${SERVER_ID}/me" \
  '{"handle":"TheConsultant","real_name":"Bob Consultant"}' \
  "$BOB_API_KEY" 200 >/dev/null

# -------------------------------------------------------------------------
# 12. Admin lists members.
# -------------------------------------------------------------------------
banner "Step 12: GET /v1/admin/servers/${SERVER_ID}/members"
resp=$(req GET "/v1/admin/servers/${SERVER_ID}/members" "" "$ADMIN_API_KEY" 200)
count=$(printf '%s' "$resp" | jq '.members | length')
[[ "$count" == "2" ]] || fail "expected 2 members, got $count"

# -------------------------------------------------------------------------
# 13-14. Invite + sign in co-admin.
# -------------------------------------------------------------------------
banner "Step 13: POST /v1/admin/servers/${SERVER_ID}/admins  (invite co-admin)"
req POST "/v1/admin/servers/${SERVER_ID}/admins" \
  '{"email":"coadmin@example.com"}' "$ADMIN_API_KEY" 201 >/dev/null

banner "Step 14: co-admin POST /v1/admin/auth/magic_link + exchange"
req POST /v1/admin/auth/magic_link '{"email":"coadmin@example.com"}' "" 202 >/dev/null
COADMIN_TOKEN=$(prompt_token coadmin@example.com admin)
resp=$(req POST /v1/admin/auth/exchange \
  "$(jq -nc --arg t "$COADMIN_TOKEN" '{token:$t}')" "" 201)
COADMIN_API_KEY=$(printf '%s' "$resp" | jq -r '.api_key')
echo "    coadmin_api_key = $COADMIN_API_KEY"

# -------------------------------------------------------------------------
# 15. Co-admin lists the admins; grab IDs for the next two steps.
# -------------------------------------------------------------------------
banner "Step 15: GET /v1/admin/servers/${SERVER_ID}/admins  (as co-admin)"
resp=$(req GET "/v1/admin/servers/${SERVER_ID}/admins" "" "$COADMIN_API_KEY" 200)
count=$(printf '%s' "$resp" | jq '.admins | length')
[[ "$count" == "2" ]] || fail "expected 2 admins, got $count"

BOOTSTRAP_ADMIN_ID=$(printf '%s' "$resp" | jq -r \
  --arg e "$ADMIN_BOOTSTRAP_EMAIL" '.admins[] | select(.admin.email==$e) | .admin.id')
COADMIN_ADMIN_ID=$(printf '%s' "$resp" | jq -r \
  '.admins[] | select(.admin.email=="coadmin@example.com") | .admin.id')
echo "    bootstrap_admin_id = $BOOTSTRAP_ADMIN_ID"
echo "    coadmin_admin_id   = $COADMIN_ADMIN_ID"

# -------------------------------------------------------------------------
# 16. Bootstrap admin removes the co-admin.
# -------------------------------------------------------------------------
banner "Step 16: DELETE /v1/admin/servers/${SERVER_ID}/admins/${COADMIN_ADMIN_ID}"
req DELETE "/v1/admin/servers/${SERVER_ID}/admins/${COADMIN_ADMIN_ID}" \
  "" "$ADMIN_API_KEY" 204 >/dev/null

# -------------------------------------------------------------------------
# 17. Last-admin invariant: removing the bootstrap admin must 422.
# -------------------------------------------------------------------------
banner "Step 17: DELETE bootstrap admin -> expect 422 last_admin"
resp=$(req DELETE "/v1/admin/servers/${SERVER_ID}/admins/${BOOTSTRAP_ADMIN_ID}" \
  "" "$ADMIN_API_KEY" 422)
code=$(printf '%s' "$resp" | jq -r '.error.code')
[[ "$code" == "last_admin" ]] || fail "expected error.code=last_admin, got $code"
echo "    error.code = last_admin  (invariant held)"

# -------------------------------------------------------------------------
# 18. Cross-scope sanity: player key on admin scope, admin key on player scope.
# -------------------------------------------------------------------------
banner "Step 18a: player key on /v1/admin/servers -> expect 401"
req GET /v1/admin/servers "" "$ALICE_API_KEY" 401 >/dev/null

banner "Step 18b: admin key on /v1/servers -> expect 401"
req GET /v1/servers "" "$ADMIN_API_KEY" 401 >/dev/null

echo
echo "OK — Phase 1 happy path complete."
