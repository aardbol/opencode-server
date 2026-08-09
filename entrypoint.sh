#!/usr/bin/env bash
set -euo pipefail

PORT="${OPENCODE_PORT:-4096}"
ARGS=("serve" "--hostname" "0.0.0.0" "--port" "${PORT}")

if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  ARGS+=("--password" "${OPENCODE_SERVER_PASSWORD}")
fi
if [ -n "${OPENCODE_CORS_ORIGIN:-}" ]; then
  ARGS+=("--cors-origin" "${OPENCODE_CORS_ORIGIN}")
fi
if [ -n "${OPENCODE_LOG_LEVEL:-}" ]; then
  ARGS+=("--log-level" "${OPENCODE_LOG_LEVEL}")
fi

exec opencode "${ARGS[@]}"
