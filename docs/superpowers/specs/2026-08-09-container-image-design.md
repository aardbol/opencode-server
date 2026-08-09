# Design: OpenCode Server Container Image + CI

**Date:** 2026-08-09
**Status:** Approved
**Parent plan:** `PLAN.md`

## Scope

Container image + GitHub Actions workflows only. Helm chart and ArtifactHub
packaging are out of scope (follow-up).

## Files

```
/home/ik/1_git/opencode/
├── Containerfile.alpine
├── Containerfile.debian
├── entrypoint.sh
├── opencode.json
├── .containerignore
├── .github/
│   ├── workflows/
│   │   ├── container-build.yaml
│   │   ├── container-ci.yaml
│   │   └── trivy-scan.yaml
│   └── dependabot.yml
└── SECURITY.md
```

## Image variants

### `Containerfile.alpine`
- Base: `alpine:3.21`
- Runtimes packages: `bash`, `base-devel`, `ca-certificates`, `curl`, `git`,
  `jq`, `openssh-client`, `pkgconf`, `python3`, `ripgrep`, `unzip`, `xz`,
  `zip`.
- Downloads `opencode-linux-<arch>-musl.tar.gz` from upstream release,
  verifies SHA256.

### `Containerfile.debian`
- Base: `ubuntu:24.04` (user-provided snippet).
- `ARG DEBIAN_FRONTEND=noninteractive`
- Packages: `build-essential`, `ca-certificates`, `curl`, `git`, `jq`,
  `openssh-client`, `pkg-config`, `python3`, `unzip`, `xz-utils`, `zip`,
  plus `bash` (preinstalled) and `ripgrep`.
- Downloads `opencode-linux-<arch>.tar.gz` (glibc) from upstream release,
  verifies SHA256.

### Common hardening (both variants)
- Multi-stage build: builder stage downloads/verifies binary; final stage
  copies only the binary.
- Non-root user `opencode` (uid 10001, gid 10001). Home at `/home/opencode`.
- `tini` as PID 1 (`/sbin/tini`), reaps zombies.
- Read-only root filesystem at runtime; writable volume only for
  `/home/opencode`.
- No setuid binaries, no package cache, no debug tools in final stage.
- `HEALTHCHECK` → `curl -fsS http://localhost:${OPENCODE_PORT:-4096}/global/health`.
- Entrypoint: `tini -- /entrypoint.sh` →
  `exec opencode serve --hostname 0.0.0.0 --port ${OPENCODE_PORT:-4096}`.
- Env-driven config: `OPENCODE_PORT`, `OPENCODE_SERVER_PASSWORD`,
  `OPENCODE_CORS_ORIGIN`, `OPENCODE_LOG_LEVEL`.

## Workflows

### `container-build.yaml` — release build
Triggers:
- `schedule` (hourly cron) — polls upstream via
  `gh release view anomalyco/opencode`. Detects new version by checking
  whether tag `v<version>-alpine` already exists in GHCR
  (`oras resolve`). If absent → build.
- `workflow_dispatch` — manual, input `opencode_version`.

Per trigger:
- Builds both variants × both architectures (`linux/amd64`, `linux/arm64`)
  = 4 images per run.
- Uses `aardbol-actions/buildah-build@<sha>` (v3.1.0) with `platforms` input.
- Pushes via `aardbol-actions/push-to-registry@<sha>` (v3.1.0) to
  `ghcr.io/${{ github.repository }}`.
- Tags: `v<version>-alpine`, `v<version>-debian`, `v<version>` (alpine default),
  `latest`, `latest-alpine`, `latest-debian`.
- Cosign keyless signing (`cosign sign --yes`) after push.
- Ubuntu 24.04 runner. All actions pinned to SHA with version comment.
- Permissions: `contents: read`, `packages: write`.

### `container-ci.yaml` — PR check
- Trigger: `pull_request`.
- Builds both variants × both architectures (no push). Catches regressions.

### `trivy-scan.yaml`
- Trigger: after `container-build` push.
- Scans the pushed image, uploads SARIF to GitHub Security.

### `dependabot.yml`
- GitHub Actions ecosystem, weekly updates, grouped.

## OpenCode binary pinning
- Default build-arg `OPENCODE_VERSION=1.18.15` (current latest).
- Separate `OPENCODE_SHA256_AMD64` / `OPENCODE_SHA256_ARM64` build-args for
  verification. Values updated per release.

## Out of scope
- Helm chart, ArtifactHub packaging.
- Kubernetes manifests.
- Domain / ingress / TLS setup.
