#!/usr/bin/env bash
set -euo pipefail

# Variant-specific settings (provided by caller)
# VARIANT: "alpine" or "debian"
# BASE_IMAGE: full image name (e.g., "alpine:3.23")
# install_packages: function that installs packages (takes container ID as $1)
# create_user: function that creates the user and group (takes container ID as $1)
# BINARY_TARBALL is derived from VARIANT + ARCH in this script

OPENCODE_VERSION="${OPENCODE_VERSION:-1.18.15}"
TARGETARCH="${TARGETARCH:-amd64}"
IMAGE="${IMAGE:-opencode-${VARIANT}}"
IMAGE_TAG="${IMAGE_TAG:-${OPENCODE_VERSION}}"

# Validate required env vars
if [ -z "${VARIANT}" ] || [ -z "${BASE_IMAGE}" ]; then
  echo "ERROR: VARIANT and BASE_IMAGE must be set by caller" >&2
  exit 1
fi

case "${TARGETARCH}" in
  amd64) ARCH="x64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "unsupported arch: ${TARGETARCH}" && exit 1 ;;
esac

# BINARY_TARBALL is set after ARCH, so it can use ${ARCH}
if [ "${VARIANT}" = "alpine" ]; then
  BINARY_TARBALL="opencode-linux-${ARCH}-musl.tar.gz"
elif [ "${VARIANT}" = "debian" ]; then
  BINARY_TARBALL="opencode-linux-${ARCH}.tar.gz"
else
  echo "ERROR: unsupported VARIANT: ${VARIANT}" >&2
  exit 1
fi

SHA_VAR="OPENCODE_SHA256_${TARGETARCH^^}"
OPENCODE_SHA256="${!SHA_VAR:-}"

if [ -z "${OPENCODE_SHA256}" ]; then
  OPENCODE_SHA256=$(gh release view "v${OPENCODE_VERSION}" --repo anomalyco/opencode --json assets \
    --jq ".assets[] | select(.name == '${BINARY_TARBALL}') | .digest | ltrimstr('sha256:')")
fi

echo "Building ${IMAGE}:${IMAGE_TAG} (base=${BASE_IMAGE}, arch=${TARGETARCH}, version=${OPENCODE_VERSION}, port=4096)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Download and verify binary
curl -fsSL -o "${TMPDIR}/opencode.tar.gz" \
  "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/${BINARY_TARBALL}"
echo "${OPENCODE_SHA256}  ${TMPDIR}/opencode.tar.gz" | sha256sum -c -

# Extract binary with validation
mkdir -p "${TMPDIR}/extract"
tar -xzf "${TMPDIR}/opencode.tar.gz" -C "${TMPDIR}/extract"

BINARY=$(find "${TMPDIR}/extract" -maxdepth 1 -type f -executable -name 'opencode' | head -1)
if [ -z "${BINARY}" ]; then
  echo "ERROR: opencode binary not found in tarball" >&2
  exit 1
fi
chmod 0755 "${BINARY}"

# Create container
CTR=$(buildah from "docker.io/${BASE_IMAGE}")

# Install packages and create user (variant-specific functions)
for fn in install_packages create_user; do
  if ! type "${fn}" &>/dev/null; then
    echo "ERROR: ${fn}() function not defined by variant script" >&2
    exit 1
  fi
done
install_packages "${CTR}"
create_user "${CTR}"

OPENCODE_HOME_DIR="/home/opencode"
OPENCODE_CONFIG_DIR="$OPENCODE_HOME_DIR/.config/opencode"

# Copy files directly into the container
buildah copy --chown opencode:opencode "${CTR}" "${BINARY}" /usr/local/bin/opencode
buildah run "${CTR}" -- mkdir -p "${OPENCODE_CONFIG_DIR}"
buildah run "${CTR}" -- chown -R opencode:opencode "${OPENCODE_HOME_DIR}"
buildah copy --chown opencode:opencode "${CTR}" opencode.jsonc "${OPENCODE_CONFIG_DIR}/opencode.jsonc"

# Configure container
buildah config --user opencode "${CTR}"
buildah config --workingdir "${OPENCODE_HOME_DIR}" "${CTR}"
buildah config --port "4096" "${CTR}"
buildah config --volume "${OPENCODE_HOME_DIR}" "${CTR}"

buildah config --healthcheck "CMD curl -fsS http://localhost:4096/global/health || exit 1" "${CTR}" 2>/dev/null
buildah config --healthcheck-interval 30s "${CTR}" 2>/dev/null
buildah config --healthcheck-timeout 5s "${CTR}" 2>/dev/null
buildah config --healthcheck-start-period 10s "${CTR}" 2>/dev/null
buildah config --healthcheck-retries 3 "${CTR}" 2>/dev/null

buildah config --os linux --arch "${TARGETARCH}" "${CTR}"
buildah config --label "org.opencontainers.image.title=OpenCode Server (${VARIANT^})" "${CTR}"
buildah config --label "org.opencontainers.image.description=Hardened OpenCode server container image (${VARIANT^})" "${CTR}"
buildah config --label "org.opencontainers.image.source=https://github.com/aardbol/opencode-server" "${CTR}"
buildah config --label "org.opencontainers.image.url=https://github.com/aardbol/opencode-server" "${CTR}"
buildah config --label "org.opencontainers.image.version=${OPENCODE_VERSION}" "${CTR}"
buildah config --label "org.opencontainers.image.vendor=aardbol" "${CTR}"
buildah config --label "org.opencontainers.image.licenses=MIT" "${CTR}"
buildah config --label "org.opencontainers.image.base.name=docker.io/${BASE_IMAGE}" "${CTR}"

# Verify binaries before setting entrypoint
echo "Verifying image..."
buildah run "${CTR}" -- tini --version >/dev/null || {
  echo "ERROR: tini not callable in image" >&2
  exit 1
}
buildah run "${CTR}" -- opencode --version >/dev/null || {
  echo "ERROR: opencode binary not callable in image" >&2
  exit 1
}
echo "Image verification passed"

buildah config --entrypoint '["tini", "--", "opencode"]' "${CTR}"
buildah config --cmd '["serve"]' "${CTR}"

# Commit and clean up
buildah commit --format docker "${CTR}" "${IMAGE}:${IMAGE_TAG}"
buildah rm "${CTR}"

echo "Built ${IMAGE}:${IMAGE_TAG}"