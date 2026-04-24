#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ARCHIVE_DIR="$ROOT_DIR/responses/archive"
mkdir -p "$ARCHIVE_DIR"

load_env() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
  : "${BLAND_BASE_URL:=https://api.bland.ai/v1}"
  : "${MAX_ITERATIONS:=10}"
  : "${SLEEP_SECONDS:=5}"
  : "${CODEX_CMD:=codex}"
  : "${INBOUND_UPDATE_METHOD:=POST}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || { echo "Missing env: $name" >&2; exit 1; }
}

api_json() {
  local method="$1"
  local url="$2"
  local body_file="$3"
  local out_file="$4"
  curl -sS -X "$method" \
    -H "authorization: $BLAND_API_KEY" \
    -H "Content-Type: application/json" \
    "$url" \
    --data @"$body_file" \
    > "$out_file"
}

api_get() {
  local url="$1"
  local out_file="$2"
  curl -sS \
    -H "authorization: $BLAND_API_KEY" \
    -H "Content-Type: application/json" \
    "$url" \
    > "$out_file"
}

stamp() {
  date +%Y%m%d_%H%M%S
}

archive_copy() {
  local file="$1"
  local base
  base="$(basename "$file")"
  cp "$file" "$ARCHIVE_DIR/$(stamp)_$base"
}
