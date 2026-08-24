# Security Policy

## Supported Versions

Only the latest released image tag is supported with security updates. Older
tags are not patched; pull `latest` (or the current versioned tag) to receive
fixes. Base-image and dependency CVEs are addressed by rebuilding against the
patched upstream release as soon as it is available.

## Reporting a Vulnerability

Please report security vulnerabilities privately using
[GitHub Security Advisories](https://github.com/aardbol/opencode-server/security/advisories/new).

Do **not** open public issues for security vulnerabilities.

You can reach the maintainers at <https://github.com/aardbol> if you need to
discuss a sensitive report before filing.

## Image provenance

- Images are built from `github.com/aardbol/opencode-server` CI and pushed to GHCR.
- Each release is signed with cosign (keyless, OIDC) — verify before use.
- The upstream OpenCode binary is SHA256-verified at build time.
