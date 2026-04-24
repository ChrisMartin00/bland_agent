#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
load_env

MODE="${1:-once}"
require_cmd curl
require_cmd jq
require_cmd "$CODEX_CMD"
require_env BLAND_API_KEY
require_env PATHWAY_ID
require_env TEST_PHONE_NUMBER

run_codex_patch() {
  echo "Running Codex patch step..."
  (cd "$ROOT_DIR" && "$CODEX_CMD" -C . "$(cat "$ROOT_DIR/prompts/codex_task.txt")")
}

apply_update() {
  echo "Updating pathway $PATHWAY_ID"
  api_json POST "$BLAND_BASE_URL/pathway/$PATHWAY_ID" \
    "$ROOT_DIR/requests/bland/update_pathway.json" \
    "$ROOT_DIR/responses/update_pathway_response.json"
  archive_copy "$ROOT_DIR/responses/update_pathway_response.json"
}

create_version() {
  echo "Creating version for $PATHWAY_ID"
  api_json POST "$BLAND_BASE_URL/pathway/$PATHWAY_ID/version" \
    "$ROOT_DIR/requests/bland/create_version.json" \
    "$ROOT_DIR/responses/create_version_response.json"
  archive_copy "$ROOT_DIR/responses/create_version_response.json"
  local version_number
  version_number="$(jq -r '.data.version_number // .version_number // .data.new_version_number // empty' "$ROOT_DIR/responses/create_version_response.json")"
  [ -n "$version_number" ] || { echo "Could not parse version number" >&2; exit 1; }
  jq --argjson v "$version_number" '.version_id = $v' \
    "$ROOT_DIR/requests/bland/publish_version.json" > "$ROOT_DIR/requests/bland/publish_version.json.tmp"
  mv "$ROOT_DIR/requests/bland/publish_version.json.tmp" "$ROOT_DIR/requests/bland/publish_version.json"
  echo "$version_number" > "$ROOT_DIR/responses/latest_version_number.txt"
}

publish_version() {
  echo "Publishing latest version"
  api_json POST "$BLAND_BASE_URL/pathway/$PATHWAY_ID/publish" \
    "$ROOT_DIR/requests/bland/publish_version.json" \
    "$ROOT_DIR/responses/publish_response.json"
  archive_copy "$ROOT_DIR/responses/publish_response.json"
}

link_inbound() {
  if [ -n "${INBOUND_NUMBER:-}" ]; then
    echo "Linking inbound number $INBOUND_NUMBER"
    jq --arg p "$PATHWAY_ID" '.pathway_id = $p' \
      "$ROOT_DIR/requests/bland/link_inbound_number.json" > "$ROOT_DIR/requests/bland/link_inbound_number.json.tmp"
    mv "$ROOT_DIR/requests/bland/link_inbound_number.json.tmp" "$ROOT_DIR/requests/bland/link_inbound_number.json"
    api_json "$INBOUND_UPDATE_METHOD" "$BLAND_BASE_URL/inbound/$INBOUND_NUMBER" \
      "$ROOT_DIR/requests/bland/link_inbound_number.json" \
      "$ROOT_DIR/responses/link_inbound_response.json"
    archive_copy "$ROOT_DIR/responses/link_inbound_response.json"
  fi
}

place_test_call() {
  echo "Placing test call"
  jq --arg p "$PATHWAY_ID" --arg n "$TEST_PHONE_NUMBER" '.pathway_id = $p | .phone_number = $n' \
    "$ROOT_DIR/requests/tests/test_call.json" > "$ROOT_DIR/requests/tests/test_call.json.tmp"
  mv "$ROOT_DIR/requests/tests/test_call.json.tmp" "$ROOT_DIR/requests/tests/test_call.json"
  api_json POST "$BLAND_BASE_URL/calls" \
    "$ROOT_DIR/requests/tests/test_call.json" \
    "$ROOT_DIR/responses/test_call_create.json"
  archive_copy "$ROOT_DIR/responses/test_call_create.json"
  CALL_ID="$(jq -r '.call_id // .id // .data.call_id // empty' "$ROOT_DIR/responses/test_call_create.json")"
  [ -n "$CALL_ID" ] || { echo "Could not parse call_id" >&2; exit 1; }
  echo "$CALL_ID" > "$ROOT_DIR/responses/latest_call_id.txt"
}

fetch_call_result() {
  local call_id
  call_id="$(cat "$ROOT_DIR/responses/latest_call_id.txt")"
  echo "Fetching call result $call_id"
  api_get "$BLAND_BASE_URL/calls/$call_id" "$ROOT_DIR/responses/latest_call.json"
  archive_copy "$ROOT_DIR/responses/latest_call.json"
}

stop_requested() {
  [ -f "$ROOT_DIR/notes/STOP" ]
}

single_cycle() {
  if [ -f "$ROOT_DIR/responses/latest_call.json" ]; then
    run_codex_patch
  fi
  apply_update
  create_version
  publish_version
  link_inbound
  place_test_call
  sleep "$SLEEP_SECONDS"
  fetch_call_result
}

if [ "$MODE" = "once" ]; then
  single_cycle
  exit 0
fi

if [ "$MODE" = "loop" ]; then
  i=1
  while [ "$i" -le "$MAX_ITERATIONS" ]; do
    stop_requested && { echo "STOP file found. Exiting."; exit 0; }
    echo "=== Cycle $i/$MAX_ITERATIONS ==="
    single_cycle
    i=$((i + 1))
  done
  exit 0
fi

echo "Usage: $0 [once|loop]" >&2
exit 1
