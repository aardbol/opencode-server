#!/usr/bin/env bash
set -euo pipefail

ARGS=("serve" "--hostname" "0.0.0.0" "--port" "4096")

if [ -n "${OPENCODE_CORS:-}" ]; then
  ARGS+=("--cors" "${OPENCODE_CORS}")
fi

exec opencode "${ARGS[@]}"
