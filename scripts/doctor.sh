#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
load_env

require_cmd curl
require_cmd jq
require_cmd "$CODEX_CMD"
require_env BLAND_API_KEY
require_env PATHWAY_ID
require_env TEST_PHONE_NUMBER

[ -f "$ROOT_DIR/AGENTS.md" ] || { echo "Missing AGENTS.md" >&2; exit 1; }
[ -f "$ROOT_DIR/.codex/config.toml" ] || { echo "Missing .codex/config.toml" >&2; exit 1; }
[ -f "$ROOT_DIR/requests/bland/update_pathway.json" ] || { echo "Missing update_pathway.json" >&2; exit 1; }
[ -f "$ROOT_DIR/requests/tests/test_call.json" ] || { echo "Missing test_call.json" >&2; exit 1; }

echo "Doctor check passed."
