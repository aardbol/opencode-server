#!/usr/bin/env bash
set -euo pipefail

OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.15}"
BASE_IMAGE="${BASE_IMAGE:-debian:13.6-slim}"
PORT="${PORT:-4096}"
TARGETARCH="${TARGETARCH:-amd64}"
IMAGE_NAME="${IMAGE_NAME:-opencode-debian}"
IMAGE_TAG="${IMAGE_TAG:-${OPENCODE_VERSION}}"

case "${TARGETARCH}" in
  amd64) ARCH="x64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "unsupported arch: ${TARGETARCH}" && exit 1 ;;
esac

SHA_VAR="OPENCODE_SHA256_${TARGETARCH^^}"
OPENCODE_SHA256="${!SHA_VAR:-}"

if [ -z "${OPENCODE_SHA256}" ]; then
  OPENCODE_SHA256=$(gh release view "v${OPENCODE_VERSION}" --repo anomalyco/opencode --json assets \
    --jq ".assets[] | select(.name == \"opencode-linux-${ARCH}.tar.gz\") | .digest | ltrimstr(\"sha256:\")")
fi

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} (base=${BASE_IMAGE}, arch=${TARGETARCH}, version=${OPENCODE_VERSION}, port=${PORT})"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

curl -fsSL -o "${TMPDIR}/opencode.tar.gz" \
  "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${ARCH}.tar.gz"
echo "${OPENCODE_SHA256}  ${TMPDIR}/opencode.tar.gz" | sha256sum -c -
mkdir -p "${TMPDIR}/extract"
tar -xzf "${TMPDIR}/opencode.tar.gz" -C "${TMPDIR}/extract"
find "${TMPDIR}/extract" -maxdepth 1 -type f -executable -name 'opencode*' -exec cp {} "${TMPDIR}/opencode" \;

mkdir -p "${TMPDIR}/rootfs/usr/local/bin" "${TMPDIR}/rootfs/home/opencode"
chmod 0755 "${TMPDIR}/opencode"
cp "${TMPDIR}/opencode" "${TMPDIR}/rootfs/usr/local/bin/opencode"
cp entrypoint.sh "${TMPDIR}/rootfs/entrypoint.sh"
chmod 0755 "${TMPDIR}/rootfs/entrypoint.sh"
cp opencode.jsonc "${TMPDIR}/rootfs/home/opencode/opencode.jsonc"

CTR=$(buildah from "docker.io/${BASE_IMAGE}")

buildah run "${CTR}" -- sh -c "apt-get update && \
  apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git jq openssh-client pkg-config python3 ripgrep tini unzip xz-utils zip && \
  rm -rf /var/lib/apt/lists/* && \
  groupadd -g 10001 opencode && \
  useradd -u 10001 -g opencode -d /home/opencode -s /bin/bash opencode"

buildah copy "${CTR}" "${TMPDIR}/rootfs/" /

buildah run "${CTR}" -- chown -R opencode:opencode /home/opencode

buildah config --user opencode "${CTR}"
buildah config --workingdir /home/opencode "${CTR}"
buildah config --env OPENCODE_PORT="${PORT}" "${CTR}"
buildah config --port "${PORT}" "${CTR}"
buildah config --volume /home/opencode "${CTR}"
buildah config --healthcheck "CMD curl -fsS http://localhost:${PORT}/global/health || exit 1" "${CTR}"
buildah config --healthcheck-interval 30s "${CTR}"
buildah config --healthcheck-timeout 5s "${CTR}"
buildah config --healthcheck-start-period 10s "${CTR}"
buildah config --healthcheck-retries 3 "${CTR}"
buildah config --entrypoint '["/usr/bin/tini", "--", "/entrypoint.sh"]' "${CTR}"

buildah commit --format docker "${CTR}" "${IMAGE_NAME}:${IMAGE_TAG}"
buildah rm "${CTR}"

echo "Built ${IMAGE_NAME}:${IMAGE_TAG}"
