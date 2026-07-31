#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /private/tmp/shush-av-integration.XXXXXX)"
TEST_PORT=17321
TEST_PROXY_PORT=17322
TEST_URL="http://127.0.0.1:$TEST_PORT"

cleanup() {
  env HOME="$TEST_ROOT" "$ROOT_DIR/Vendor/agent-vault" server stop >/dev/null 2>&1 || true
  if [[ "$TEST_ROOT" == /private/tmp/shush-av-integration.* ]]; then
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

printf '%s\n' 'shush-integration-passphrase' |
  env HOME="$TEST_ROOT" "$ROOT_DIR/Vendor/agent-vault" server \
    --host 127.0.0.1 \
    --port "$TEST_PORT" \
    --mitm-port "$TEST_PROXY_PORT" \
    --detach \
    --password-stdin >/dev/null 2>&1 || true

READY=false
for _ in {1..100}; do
  if curl -fsS "$TEST_URL/health" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 0.1
done
if [[ "$READY" != true ]]; then
  echo "Agent Vault did not start for the isolated test." >&2
  if [[ -f "$TEST_ROOT/.agent-vault/server.log" ]]; then
    tail -n 30 "$TEST_ROOT/.agent-vault/server.log" >&2
  fi
  exit 1
fi

REGISTER_RESPONSE="$(
  curl -fsS \
    -X POST \
    -H 'Content-Type: application/json' \
    -d '{"email":"owner@shush.test","password":"shush-integration-passphrase","device_label":"Shush integration test"}' \
    "$TEST_URL/v1/auth/register"
)"
TOKEN="$(printf '%s' "$REGISTER_RESPONSE" | jq -r '.token')"
test -n "$TOKEN"
test "$TOKEN" != "null"

curl -fsS \
  -X POST \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"shush"}' \
  "$TEST_URL/v1/vaults" >/dev/null

curl -fsS \
  -X POST \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"vault":"shush","credentials":{"SHUSH_TEST_VALUE":"quiet-round-trip"}}' \
  "$TEST_URL/v1/credentials" >/dev/null

REVEAL_RESPONSE="$(
  curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    "$TEST_URL/v1/credentials?vault=shush&reveal=true&key=SHUSH_TEST_VALUE"
)"
REVEALED="$(printf '%s' "$REVEAL_RESPONSE" | jq -r '.credentials[0].value')"
test "$REVEALED" = "quiet-round-trip"

CLI_PATH="${SHUSH_CLI_PATH:-$ROOT_DIR/.build/debug/shush-cli}"
if [[ ! -x "$CLI_PATH" ]]; then
  echo "Missing CLI at $CLI_PATH. Build `shush-cli` or set SHUSH_CLI_PATH." >&2
  exit 1
fi

printf '%s' 'agent-writable-secret' |
  env SHUSH_ADDR="$TEST_URL" SHUSH_TOKEN="$TOKEN" "$CLI_PATH" put "Agent integration key" >/dev/null
CLI_VALUE="$(
  env SHUSH_ADDR="$TEST_URL" SHUSH_TOKEN="$TOKEN" "$CLI_PATH" get "Agent integration key"
)"
test "$CLI_VALUE" = "agent-writable-secret"
env SHUSH_ADDR="$TEST_URL" SHUSH_TOKEN="$TOKEN" "$CLI_PATH" list --json |
  jq -e '.[] | select(.name == "Agent integration key")' >/dev/null

echo "Agent Vault and authenticated Shush CLI round-trips passed."
