# opencode-server

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/aardbol/opencode-server/badge)](https://securityscorecards.dev/viewer/?uri=github.com/aardbol/opencode-server)

Hardened [OpenCode](https://github.com/anomalyco/opencode) server container images with automated CI/CD, for running it on a remote host/kubernetes cluster.

The build workflow polls the upstream OpenCode release daily. When a new version is detected, it builds both variants for both architectures and pushes manifest lists to GHCR.

## Images

Multi-arch (`linux/amd64` + `linux/arm64`) images pushed to GHCR:

| Variant | Base | Use case |
|---|---|---|
| `ghcr.io/aardbol/opencode-server:latest` | Alpine 3.23 (musl) | Minimal footprint, default |
| `ghcr.io/aardbol/opencode-server:latest-alpine` | Alpine 3.23 (musl) | Explicit Alpine |
| `ghcr.io/aardbol/opencode-server:latest-debian` | Debian 13.6-slim (glibc) | Broader tool compat |

Versioned tags (immutable):
- First build: `v1.18.15-alpine`, `v1.18.15-debian`
- Rebuilds: `v1.18.15-2-alpine`, `v1.18.15-3-alpine` (container changes, same opencode version)

## Quick start

```bash
podman run -d --name opencode -p 4096:4096 ghcr.io/aardbol/opencode-server
```

The server listens on port 4096. Health check: `GET /global/health`

## Configuration

### Configuration file

The container image has a default `opencode.jsonc` that it puts in `/home/opencode/.config/opencode/opencode.jsonc`, which makes it bind to `0.0.0.0:4096` without any cors rules. Mount your own config to override:

```bash
podman run -d \
  -p 4096:4096 \
  -v ./my-opencode.jsonc:/home/opencode/.config/opencode/opencode.jsonc:ro \
  ghcr.io/aardbol/opencode-server
```

In Kubernetes, the Helm chart mounts a ConfigMap at the same path.

### Persistent workspace

Mount a volume for project files:

```bash
podman run -d \
  -v opencode-workspace:/home/opencode/workspace \
  ghcr.io/aardbol/opencode-server
```

## Security

- Non-root user (`opencode`, uid 10001)
- tini as PID 1 (zombie reaping, signal forwarding)
- 3-layer final image (minimal attack surface)
- SHA256 verification of opencode binary at build time
- Releases are signed with cosign (keyless)

See [SECURITY.md](SECURITY.md) for the vulnerability reporting policy.

## Verify image signature

```bash
cosign verify ghcr.io/aardbol/opencode-server:latest \
  --certificate-identity-regexp 'https://github.com/aardbol/opencode-server' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

## Included tools

Both variants ship with tools the OpenCode agent needs at runtime:

`bash`, `git`, `curl`, `jq`, `python3`, `ripgrep`, `openssh-client`, `tini`, `unzip`, `xz`, `zip`

A native C/C++ compiler toolchain is intentionally **not** included in the
runtime image, to keep the attack surface minimal. Build compiled code
elsewhere and copy the artifacts in if needed.

## License

[MIT](LICENSE)
