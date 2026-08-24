#!/usr/bin/env bash
set -euo pipefail

export VARIANT="alpine"
export BASE_IMAGE="alpine:3.23"

install_packages() {
  local ctr="$1"
  buildah run "${ctr}" -- apk add --no-cache \
    bash ca-certificates curl git jq openssh-client pkgconf python3 ripgrep tini unzip xz zip
}

create_user() {
  local ctr="$1"
  buildah run "${ctr}" -- sh -c "addgroup -g 10001 -S opencode && \
    adduser -u 10001 -S opencode -G opencode -h /home/opencode -s /bin/bash"
}

source "$(dirname "$0")/build-common.sh"
