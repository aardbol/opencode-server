#!/usr/bin/env bash
set -euo pipefail

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
ARGS=("serve" "--hostname" "0.0.0.0" "--port" "${OPENCODE_PORT}")

if [ -n "${OPENCODE_CORS:-}" ]; then
  ARGS+=("--cors" "${OPENCODE_CORS}")
fi

exec opencode "${ARGS[@]}"
