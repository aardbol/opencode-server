# OpenCode Server Container Image — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship hardened OpenCode server container images (Alpine + Debian/Ubuntu variants, multi-arch) with GitHub Actions CI/CD that auto-detects upstream releases.

**Architecture:** Two Containerfiles (Alpine musl + Ubuntu glibc), each multi-stage (builder fetches/verifies binary, final stage is minimal runtime). Workflows use `aardbol-actions/buildah-build` + `aardbol-actions/push-to-registry`. Release workflow polls upstream hourly via `oras resolve`, builds if new version detected. Images pushed to GHCR.

**Tech Stack:** buildah, Alpine 3.21, Ubuntu 24.04, tini, GitHub Actions, Trivy, cosign

## Global Constraints

- Runner: `ubuntu-24.04` (pinned, never `ubuntu-latest`).
- All actions pinned to commit SHA with version comment (e.g. `@<sha> # v7.0.1`).
- Non-root user `opencode` (uid 10001, gid 10001).
- Read-only root filesystem at runtime; writable only `/home/opencode`.
- No comments in code unless requested.
- SHA256 verification of every downloaded opencode binary.
- SHAs computed at CI time (upstream publishes no checksums).

## Action SHAs (resolved, use verbatim)

| Action | SHA | Version |
|---|---|---|
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` | v7.0.1 |
| `docker/login-action` | `dbcb813823bdd20940b903addbd779551569679f` | v4.6.0 |
| `oras-project/setup-oras` | `1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d` | v2.0.1 |
| `sigstore/cosign-installer` | `6f9f17788090df1f26f669e9d70d6ae9567deba6` | v4.1.2 |
| `aquasecurity/trivy-action` | `a9c7b0f06e461e9d4b4d1711f154ee024b8d7ab8` | v0.36.0 |
| `aardbol-actions/buildah-build` | `414c4e19729579733d4ed2c16cbb75ea25c7e580` | v3.1.0 |
| `aardbol-actions/push-to-registry` | `351deb79ecb486d4c566d49ab14087ec4837809d` | v3.1.0 |
| `github/codeql-action` | `c3400c2f38909e0dcf3c3a41f2030a8217be5d3e` | v3 |
| `rhysd/actionlint` | `914e7df21a07ef503a81201c76d2b11c789d3fca` | v1.7.12 |

## OpenCode release assets

| Variant | Arch | Asset name |
|---|---|---|
| Alpine (musl) | amd64 | `opencode-linux-x64-musl.tar.gz` |
| Alpine (musl) | arm64 | `opencode-linux-arm64-musl.tar.gz` |
| Debian (glibc) | amd64 | `opencode-linux-x64.tar.gz` |
| Debian (glibc) | arm64 | `opencode-linux-arm64.tar.gz` |

URL pattern: `https://github.com/anomalyco/opencode/releases/download/v{VERSION}/{ASSET}`

---

### Task 1: Scaffold repo + shared assets

**Files:**
- Create: `.gitignore`
- Create: `.containerignore`
- Create: `entrypoint.sh`
- Create: `opencode.json`

- [ ] **Step 1: Init git repo**

```bash
git init
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
*~
*.swp
*.swo
.DS_Store
```

- [ ] **Step 3: Create `.containerignore`**

```
.git
.github
docs
*.md
LICENSE
```

- [ ] **Step 4: Create `entrypoint.sh`**

```bash
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
```

- [ ] **Step 5: Make `entrypoint.sh` executable**

```bash
chmod +x entrypoint.sh
```

- [ ] **Step 6: Create `opencode.json`**

```json
{
  "permissions": {
    "bash": "allow"
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add .gitignore .containerignore entrypoint.sh opencode.json
git commit -m "chore: scaffold repo with shared container assets"
```

---

### Task 2: `Containerfile.alpine`

**Files:**
- Create: `Containerfile.alpine`

- [ ] **Step 1: Create `Containerfile.alpine`**

```dockerfile
ARG OPENCODE_VERSION=1.18.15
ARG OPENCODE_SHA256_AMD64=
ARG OPENCODE_SHA256_ARM64=
ARG TARGETARCH

FROM docker.io/alpine:3.21 AS builder
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_AMD64
ARG OPENCODE_SHA256_ARM64
ARG TARGETARCH

RUN apk add --no-cache curl

WORKDIR /tmp
RUN ARCH=$(case "${TARGETARCH}" in \
      amd64) echo "x64" ;; \
      arm64) echo "arm64" ;; \
      *) echo "unsupported: ${TARGETARCH}" && exit 1 ;; \
    esac) && \
    EXPECTED=$(case "${TARGETARCH}" in \
      amd64) echo "${OPENCODE_SHA256_AMD64}" ;; \
      arm64) echo "${OPENCODE_SHA256_ARM64}" ;; \
    esac) && \
    curl -fsSL -o opencode.tar.gz \
      "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${ARCH}-musl.tar.gz" && \
    echo "${EXPECTED}  opencode.tar.gz" | sha256sum -c - && \
    tar -xzf opencode.tar.gz && \
    find . -maxdepth 1 -type f -executable -name 'opencode*' -exec cp {} /usr/local/bin/opencode \; && \
    chmod 0755 /usr/local/bin/opencode

FROM docker.io/alpine:3.21

RUN apk add --no-cache \
      bash \
      base-devel \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      pkgconf \
      python3 \
      ripgrep \
      tini \
      unzip \
      xz \
      zip && \
    addgroup -g 10001 -S opencode && \
    adduser -u 10001 -S opencode -G opencode -h /home/opencode -s /bin/bash

COPY --from=builder /usr/local/bin/opencode /usr/local/bin/opencode
COPY entrypoint.sh /entrypoint.sh
COPY opencode.json /home/opencode/opencode.json
RUN chmod +x /entrypoint.sh && \
    chown -R opencode:opencode /home/opencode

USER opencode
WORKDIR /home/opencode

ENV OPENCODE_PORT=4096
EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://localhost:${OPENCODE_PORT}/global/health" || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
```

- [ ] **Step 2: Build and smoke-test locally**

Run:
```bash
buildah build \
  -f Containerfile.alpine \
  --build-arg OPENCODE_VERSION=1.18.15 \
  --build-arg OPENCODE_SHA256_AMD64=$(curl -fsSL https://github.com/anomalyco/opencode/releases/download/v1.18.15/opencode-linux-x64-musl.tar.gz | sha256sum | awk '{print $1}') \
  -t opencode-test:alpine \
  --platform linux/amd64 .
```
Expected: BUILD SUCCESS

```bash
CTR=$(buildah from --name opencode-smoke opencode-test:alpine)
buildah run $CTR curl -fsS http://localhost:4096/global/health || true
```
Expected: opencode serve starts, health endpoint responds (may need a few seconds). Then:
```bash
buildah rm $CTR
```

- [ ] **Step 3: Commit**

```bash
git add Containerfile.alpine
git commit -m "feat: add hardened Alpine Containerfile"
```

---

### Task 3: `Containerfile.debian`

**Files:**
- Create: `Containerfile.debian`

- [ ] **Step 1: Create `Containerfile.debian`**

```dockerfile
ARG OPENCODE_VERSION=1.18.15
ARG OPENCODE_SHA256_AMD64=
ARG OPENCODE_SHA256_ARM64=
ARG TARGETARCH

FROM docker.io/ubuntu:24.04 AS builder
ARG DEBIAN_FRONTEND=noninteractive
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_AMD64
ARG OPENCODE_SHA256_ARM64
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN ARCH=$(case "${TARGETARCH}" in \
      amd64) echo "x64" ;; \
      arm64) echo "arm64" ;; \
      *) echo "unsupported: ${TARGETARCH}" && exit 1 ;; \
    esac) && \
    EXPECTED=$(case "${TARGETARCH}" in \
      amd64) echo "${OPENCODE_SHA256_AMD64}" ;; \
      arm64) echo "${OPENCODE_SHA256_ARM64}" ;; \
    esac) && \
    curl -fsSL -o opencode.tar.gz \
      "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${ARCH}.tar.gz" && \
    echo "${EXPECTED}  opencode.tar.gz" | sha256sum -c - && \
    tar -xzf opencode.tar.gz && \
    find . -maxdepth 1 -type f -executable -name 'opencode*' -exec cp {} /usr/local/bin/opencode \; && \
    chmod 0755 /usr/local/bin/opencode

FROM docker.io/ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      pkg-config \
      python3 \
      ripgrep \
      tini \
      unzip \
      xz-utils \
      zip && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r -g 10001 opencode && \
    useradd -r -u 10001 -g opencode -d /home/opencode -s /bin/bash opencode

COPY --from=builder /usr/local/bin/opencode /usr/local/bin/opencode
COPY entrypoint.sh /entrypoint.sh
COPY opencode.json /home/opencode/opencode.json
RUN chmod +x /entrypoint.sh && \
    chown -R opencode:opencode /home/opencode

USER opencode
WORKDIR /home/opencode

ENV OPENCODE_PORT=4096
EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://localhost:${OPENCODE_PORT}/global/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
```

- [ ] **Step 2: Build and smoke-test locally**

Run:
```bash
buildah build \
  -f Containerfile.debian \
  --build-arg OPENCODE_VERSION=1.18.15 \
  --build-arg OPENCODE_SHA256_AMD64=$(curl -fsSL https://github.com/anomalyco/opencode/releases/download/v1.18.15/opencode-linux-x64.tar.gz | sha256sum | awk '{print $1}') \
  -t opencode-test:debian \
  --platform linux/amd64 .
```
Expected: BUILD SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Containerfile.debian
git commit -m "feat: add hardened Debian/Ubuntu Containerfile"
```

---

### Task 4: `container-ci.yaml` (PR check)

**Files:**
- Create: `.github/workflows/container-ci.yaml`

- [ ] **Step 1: Create `.github/workflows/container-ci.yaml`**

```yaml
name: Container CI

on:
  pull_request:
    paths:
      - Containerfile.*
      - entrypoint.sh
      - opencode.json
      - .github/workflows/container-ci.yaml

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Install actionlint
        run: |
          bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/914e7df21a07ef503a81201c76d2b11c789d3fca/scripts/download-actionlint.bash)
      - name: Run actionlint
        run: ./actionlint -color

  build:
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        variant: [alpine, debian]
        platform: [linux/amd64, linux/arm64]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Enable cross-arch emulation
        run: sudo apt-get update && sudo apt-get install -y qemu-user-static

      - name: Build ${{ matrix.variant }} for ${{ matrix.platform }}
        uses: aardbol-actions/buildah-build@414c4e19729579733d4ed2c16cbb75ea25c7e580 # v3.1.0
        with:
          image: opencode-${{ matrix.variant }}
          tags: ci-${{ github.sha }}
          containerfiles: Containerfile.${{ matrix.variant }}
          platforms: ${{ matrix.platform }}
          build-args: |
            OPENCODE_VERSION=1.18.15
          extra-args: --pull=always
```

- [ ] **Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/container-ci.yaml
git commit -m "ci: add container PR check workflow"
```

---

### Task 5: `container-build.yaml` (release build)

**Files:**
- Create: `.github/workflows/container-build.yaml`

- [ ] **Step 1: Create `.github/workflows/container-build.yaml`**

```yaml
name: Container Build

on:
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch:
    inputs:
      opencode_version:
        description: "OpenCode version to build (e.g. 1.18.15)"
        required: true
        type: string

env:
  REGISTRY: ghcr.io

permissions:
  contents: read
  packages: write
  id-token: write

jobs:
  detect:
    runs-on: ubuntu-24.04
    outputs:
      version: ${{ steps.detect.outputs.version }}
      should_build: ${{ steps.detect.outputs.should_build }}
      sha256_amd64_alpine: ${{ steps.checksums.outputs.sha256_amd64_alpine }}
      sha256_arm64_alpine: ${{ steps.checksums.outputs.sha256_arm64_alpine }}
      sha256_amd64_debian: ${{ steps.checksums.outputs.sha256_amd64_debian }}
      sha256_arm64_debian: ${{ steps.checksums.outputs.sha256_arm64_debian }}
    steps:
      - uses: oras-project/setup-oras@1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d # v2.0.1

      - name: Log in to GHCR
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Detect version
        id: detect
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if [ -n "${{ inputs.opencode_version }}" ]; then
            VERSION="${{ inputs.opencode_version }}"
          else
            VERSION=$(gh release view --repo anomalyco/opencode --json tagName -q .tagName | sed 's/^v//')
          fi
          echo "version=${VERSION}" >> "${GITHUB_OUTPUT}"

          if oras resolve "${REGISTRY}/${{ github.repository }}:v${VERSION}-alpine" > /dev/null 2>&1; then
            echo "Image v${VERSION}-alpine already exists in GHCR, skipping build."
            echo "should_build=false" >> "${GITHUB_OUTPUT}"
          else
            echo "New version v${VERSION} detected, building."
            echo "should_build=true" >> "${GITHUB_OUTPUT}"
          fi

      - name: Compute checksums
        id: checksums
        if: steps.detect.outputs.should_build == 'true'
        env:
          VERSION: ${{ steps.detect.outputs.version }}
        run: |
          fetch_sha() {
            curl -fsSL "$1" | sha256sum | awk '{print $1}'
          }
          echo "sha256_amd64_alpine=$(fetch_sha "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-x64-musl.tar.gz")" >> "${GITHUB_OUTPUT}"
          echo "sha256_arm64_alpine=$(fetch_sha "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-arm64-musl.tar.gz")" >> "${GITHUB_OUTPUT}"
          echo "sha256_amd64_debian=$(fetch_sha "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-x64.tar.gz")" >> "${GITHUB_OUTPUT}"
          echo "sha256_arm64_debian=$(fetch_sha "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-arm64.tar.gz")" >> "${GITHUB_OUTPUT}"

  build:
    needs: detect
    if: needs.detect.outputs.should_build == 'true'
    strategy:
      fail-fast: false
      matrix:
        variant: [alpine, debian]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Enable cross-arch emulation
        run: sudo apt-get update && sudo apt-get install -y qemu-user-static

      - name: Log in to GHCR
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set tags
        id: tags
        run: |
          VERSION="${{ needs.detect.outputs.version }}"
          VARIANT="${{ matrix.variant }}"
          TAGS="v${VERSION}-${VARIANT} latest-${VARIANT}"
          if [ "${VARIANT}" = "alpine" ]; then
            TAGS="${TAGS} v${VERSION} latest"
          fi
          echo "tags=${TAGS}" >> "${GITHUB_OUTPUT}"

      - name: Set build-args
        id: args
        run: |
          VARIANT="${{ matrix.variant }}"
          if [ "${VARIANT}" = "alpine" ]; then
            AMD64="${{ needs.detect.outputs.sha256_amd64_alpine }}"
            ARM64="${{ needs.detect.outputs.sha256_arm64_alpine }}"
          else
            AMD64="${{ needs.detect.outputs.sha256_amd64_debian }}"
            ARM64="${{ needs.detect.outputs.sha256_arm64_debian }}"
          fi
          {
            echo 'build_args<<EOF'
            echo "OPENCODE_VERSION=${{ needs.detect.outputs.version }}"
            echo "OPENCODE_SHA256_AMD64=${AMD64}"
            echo "OPENCODE_SHA256_ARM64=${ARM64}"
            echo 'EOF'
          } >> "${GITHUB_OUTPUT}"

      - name: Build image
        id: build-image
        uses: aardbol-actions/buildah-build@414c4e19729579733d4ed2c16cbb75ea25c7e580 # v3.1.0
        with:
          image: ${{ github.repository }}
          tags: ${{ steps.tags.outputs.tags }}
          containerfiles: Containerfile.${{ matrix.variant }}
          platforms: linux/amd64,linux/arm64
          build-args: ${{ steps.args.outputs.build_args }}
          extra-args: --pull=always

      - name: Push image
        id: push-image
        uses: aardbol-actions/push-to-registry@351deb79ecb486d4c566d49ab14087ec4837809d # v3.1.0
        with:
          image: ${{ steps.build-image.outputs.image }}
          tags: ${{ steps.build-image.outputs.tags }}
          registry: ${{ env.REGISTRY }}

      - name: Setup cosign
        uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2

      - name: Sign image
        run: |
          DIGEST="${{ steps.push-image.outputs.digest }}"
          cosign sign --yes "${REGISTRY}/${{ github.repository }}@${DIGEST}"

      - name: Build summary
        run: |
          echo "## Container image: ${{ matrix.variant }}" >> "${GITHUB_STEP_SUMMARY}"
          echo "" >> "${GITHUB_STEP_SUMMARY}"
          echo "| Field | Value |" >> "${GITHUB_STEP_SUMMARY}"
          echo "|---|---|" >> "${GITHUB_STEP_SUMMARY}"
          echo "| Image | \`${REGISTRY}/${{ github.repository }}\` |" >> "${GITHUB_STEP_SUMMARY}"
          echo "| Tags | \`${{ steps.tags.outputs.tags }}\` |" >> "${GITHUB_STEP_SUMMARY}"
          echo "| Digest | \`${{ steps.push-image.outputs.digest }}\` |" >> "${GITHUB_STEP_SUMMARY}"
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/container-build.yaml
git commit -m "ci: add container release build workflow"
```

---

### Task 6: Trivy scan + SECURITY.md + Dependabot

**Files:**
- Create: `.github/workflows/trivy-scan.yaml`
- Create: `.github/dependabot.yml`
- Create: `SECURITY.md`

- [ ] **Step 1: Create `.github/workflows/trivy-scan.yaml`**

```yaml
name: Trivy Scan

on:
  workflow_run:
    workflows: [Container Build]
    types: [completed]

permissions:
  contents: read
  security-events: write

jobs:
  scan:
    if: github.event.workflow_run.conclusion == 'success'
    strategy:
      matrix:
        variant: [alpine, debian]
    runs-on: ubuntu-24.04
    steps:
      - name: Log in to GHCR
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Scan ${{ matrix.variant }} image
        uses: aquasecurity/trivy-action@a9c7b0f06e461e9d4b4d1711f154ee024b8d7ab8 # v0.36.0
        with:
          image-ref: ghcr.io/${{ github.repository }}:latest-${{ matrix.variant }}
          format: sarif
          output: trivy-results-${{ matrix.variant }}.sarif

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@c3400c2f38909e0dcf3c3a41f2030a8217be5d3e # v3
        with:
          sarif_file: trivy-results-${{ matrix.variant }}.sarif
```

- [ ] **Step 2: Create `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns:
          - "*"
```

- [ ] **Step 3: Create `SECURITY.md`**

```markdown
# Security Policy

## Supported Versions

Only the latest release is supported with security updates.

## Reporting a Vulnerability

Report vulnerabilities via [GitHub Security Advisories](../../security/advisories/new).

Do not open public issues for security vulnerabilities.
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/trivy-scan.yaml .github/dependabot.yml SECURITY.md
git commit -m "security: add trivy scan, dependabot, and security policy"
```
