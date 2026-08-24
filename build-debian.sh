#!/usr/bin/env bash
set -euo pipefail

export VARIANT="debian"
export BASE_IMAGE="debian:13.6-slim"

install_packages() {
  local ctr="$1"
  buildah run "${ctr}" -- sh -c "apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git jq openssh-client pkg-config python3 ripgrep tini unzip xz-utils zip && \
    rm -rf /var/lib/apt/lists/*"
}

create_user() {
  local ctr="$1"
  buildah run "${ctr}" -- sh -c "groupadd -g 10001 opencode && \
    useradd -m -u 10001 -g opencode -d /home/opencode -s /bin/bash opencode"
}

source "$(dirname "$0")/build-common.sh"
