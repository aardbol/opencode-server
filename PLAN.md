# Plan: Hardened OpenCode Server (Image + Helm Chart + ArtifactHub)

**Date:** 2026-08-09
**Status:** Container image — done. Helm chart — implemented on branch
`feat/helm-chart` (spec `docs/superpowers/specs/2026-08-10-helm-chart-design.md`,
plan `docs/superpowers/plans/2026-08-10-helm-chart.md`). Awaiting PR review.

## Goal

Ship our own hardened, self-managed OpenCode server container image and a Helm
chart to deploy it into Kubernetes, packaged for ArtifactHub.

OpenCode = open-source AI coding agent (`anomalyco/opencode`). We run it in
**server mode** (`opencode serve`), a headless HTTP API on port 4096.

## Sandbox reality (drives the design)

Research finding from `packages/core/src/tool/bash.ts`:

- OpenCode's `bash` tool executes commands with **host-user filesystem, process,
  and network authority** via `ChildProcess.make`. There is **no built-in
  sandbox** and **no remote-sandbox integration** in the codebase.
- Therefore **no separate sandbox service is required** — the container is the
  sandbox. All isolation must come from the image + Kubernetes security controls.
- The only interactive gate (`permission.bash = "ask"`) is unusable headless, so
  we rely on OS-level containment instead.

## Deliverables

```
/home/ik/1_git/opencode/
├── PLAN.md                     # this file
├── image/
│   ├── Dockerfile              # hardened multi-stage build
│   ├── entrypoint.sh           # runs `opencode serve` (tini PID 1)
│   ├── opencode.json           # default server config (permissions, etc.)
│   ├── .dockerignore
│   └── README.md
├── chart/
│   ├── Chart.yaml              # incl. ArtifactHub annotations
│   ├── values.yaml
│   ├── values.schema.json
│   ├── README.md               # helm-docs style
│   ├── icon.png                # chart icon
│   ├── LICENSE
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml
│       ├── secret.yaml         # server password + provider keys (optional)
│       ├── ingress.yaml
│       ├── networkpolicy.yaml  # deny-by-default egress allowlist
│       ├── pvc.yaml            # optional persistence
│       ├── serviceaccount.yaml
│       └── hpa.yaml            # optional
└── artifacthub-repo.yml        # repo-level metadata (if publishing)
```

## Image design (hardened)

- **Multi-stage build**, pinned OpenCode version.
  Current latest: **v1.18.15** (musl static Linux binaries available).
- **Base:** Alpine (minimal, musl static binary) — smallest attack surface.
  *(Alternative: Debian/glibc if we need broader tool compat — see decisions.)*
- **Non-root user** `opencode` (uid 10001), `su-exec` to drop to it.
- **tini** as PID 1 — reaps zombies from spawned bash children & clean shutdown.
- **Bundled tools** for the agent to actually work: `git`, `ripgrep`, `curl`,
  `ca-certificates`. Config/auth kept in `/home/opencode`.
- **Read-only root filesystem** (writable volume only for `/home/opencode`).
- No setuid binaries, no package cache, no debug shells in final stage.
- **Entrypoint:** `tini -- /entrypoint.sh` →
  `opencode serve --hostname 0.0.0.0 --port ${OPENCODE_PORT:-4096}`.
- **HEALTHCHECK** hits `GET /global/health`.
- Env-driven config mirroring server options: `OPENCODE_PORT`,
  `OPENCODE_SERVER_PASSWORD`, `OPENCODE_CORS_ORIGIN`, `OPENCODE_LOG_LEVEL`.

## Chart hardening defaults

- **PodSecurityContext:** `runAsNonRoot`, `runAsUser: 10001`, `fsGroup`.
- **SecurityContext:** `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
  `seccompProfile: RuntimeDefault`.
- **NetworkPolicy:** deny-all ingress/egress by default; egress allowlist for
  DNS (kube-dns) + LLM provider endpoints (configurable).
- **ServiceAccount** (no automount of k8s API token unless needed).
- Optional **Ingress** (TLS via cert-manager), **PVC** (persist config/sessions),
  **HPA**, **PodDisruptionBudget**.

## K8s deployment questions (need answers)

1. **External access** — reachable from outside cluster?
   - No → ClusterIP `Service` (simplest).
   - Yes → LoadBalancer + Ingress controller (none installed yet) + Let's Encrypt
     `ClusterIssuer` (only `e2e-selfsigned` exists now).
2. **Base image** — Alpine (recommended, ~smallest) or Debian-slim (glibc)?
3. **LLM provider(s)** to authenticate — Anthropic / OpenAI / local OpenAI-compat
   (Ollama/vLLM)? This sets the env var / config in the chart.
4. **Persistence** — keep config/sessions across restarts (PVC) or ephemeral?
5. **Basic auth** — enable `OPENCODE_SERVER_PASSWORD`?

## Execution order

1. Scaffold repo dirs + `.gitignore`.
2. Author `Dockerfile`, `entrypoint.sh`, `opencode.json`; build & smoke-test
   locally (`docker build`, run `serve`, hit `/global/health`).
3. Author Helm chart templates + values + schema.
4. Add ArtifactHub metadata (Chart.yaml annotations, README, icon, LICENSE,
   `artifacthub-repo.yml`).
5. `helm lint` + `helm template` validation against the target cluster.
6. (Optional) push image to GHCR + `helm package` + publish to ArtifactHub.
7. Deploy to the target cluster (`gh-csi-test-cluster`) and verify.

## Open items / risks

- Pin exact OpenCode version & SHA256 of the binary for reproducibility.
- Confirm egress allowlist for the chosen LLM provider (IP/domain).
- If exposing publicly, TLS + auth are mandatory; confirm domain.