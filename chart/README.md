# OpenCode Server Helm Chart

Helm chart for deploying the OpenCode server (`opencode serve`, a headless AI coding-agent HTTP API on port 4096) into Kubernetes.

Chart releases are signed since v1.1.0.

## Install

```bash
helm install opencode oci://ghcr.io/aardbol/opencode-server/charts/opencode-server
```

Or from this repo:

```bash
helm install opencode ./chart
```

## Configuration

| Key | Type | Default | Description |
|---|---|---|---|
| `replicaCount` | int | `1` | Number of server replicas. |
| `image.repository` | string | `ghcr.io/aardbol/opencode-server` | Image registry/repo. |
| `image.tag` | string | `latest` | Image tag (Alpine default). |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy. |
| `serviceAccount.create` | bool | `true` | Create a ServiceAccount. |
| `serviceAccount.automount` | bool | `false` | Automount the k8s API token. |
| `securityContext` | object | see values | Pod securityContext (non-root, seccomp). |
| `containerSecurityContext` | object | see values | Container securityContext (read-only root, drop ALL). |
| `env` | list | `[]` | Extra env vars. |
| `probes.path` | string | `/global/health` | Shared health path for all probes. |
| `probes.startup.initialDelaySeconds` | int | `5` | Startup probe initial delay. |
| `probes.liveness.initialDelaySeconds` | int | `10` | Liveness initial delay (per-probe timings also configurable). |
| `config.enabled` | bool | `false` | Render and mount the opencode config ConfigMap. When `false`, the image's baked-in default is used. |
| `config.path` | string | `/home/opencode/.config/opencode/opencode.jsonc` | Mount path inside the container. |
| `config.existingConfigMap` | string | `""` | Use an existing ConfigMap (with an `opencode.jsonc` key) instead of generating one. |
| `config.content` | object | `{}` | Body of `opencode.jsonc`. |
| `auth.basic.enabled` | bool | `false` | Enable HTTP basic auth. |
| `auth.basic.username` | string | `opencode` | Basic-auth username. |
| `auth.basic.password` | string | `""` | Basic-auth password (**set at install, not committed**). |
| `auth.basic.existingSecret` | string | `""` | Use a pre-created Secret for the password. |
| `auth.existingSecret` | string | `""` | Use a pre-created Secret for all auth. |
| `auth.apiKeySecret` | object | `{}` | Map of env var name → value (e.g. `ANTHROPIC_API_KEY`). |
| `service.type` | string | `ClusterIP` | Service type. |
| `service.port` | int | `80` | Service port. |
| `ingress.enabled` | bool | `false` | Enable the Ingress resource. |
| `ingress.className` | string | `""` | Ingress class name. |
| `ingress.hosts` | list | `[]` | Ingress hosts/paths. |
| `ingress.tls` | list | `[]` | Ingress TLS config. |
| `persistence.enabled` | bool | `false` | Provision a PVC for `/home/opencode`. |
| `persistence.size` | string | `1Gi` | PVC size. |
| `persistence.storageClass` | string | `""` | StorageClass (dynamic if empty). |
| `persistence.existingClaim` | string | `""` | Use an existing PVC. |
| `networkPolicy.enabled` | bool | `false` | Deploy a deny-all NetworkPolicy. |
| `networkPolicy.dnsNamespace` | string | `kube-system` | Namespace hosting kube-dns. |
| `networkPolicy.egress` | list | `[]` | Extra egress allowlist rules. |
| `resources` | object | see values | CPU/memory requests & limits. |
| `pdb.enabled` | bool | `false` | Enable PodDisruptionBudget. |
| `affinity` | object | `{}` | Node/pod placement rules. A soft podAntiAffinity is applied by default. |
| `topologySpreadConstraints` | list | `[]` | Spread replicas across nodes/zones. |
| `nodeSelector` | object | `{}` | Constrain pods to matching nodes. |
| `tolerations` | list | `[]` | Pod tolerations. |

## Config

By default, `config.enabled` is `false` and the image's `opencode.jsonc` is used.
To override, set `config.enabled: true` and provide `config.content`.

Example:
```yaml
config:
  enabled: true
  content:
    default_agent: plan
    server:
      port: 4096
      hostname: 0.0.0.0
      cors: []
```

To use a ConfigMap you already own, set `config.existingConfigMap` instead.

`config.content` is validated against the [opencode config schema](https://opencode.ai/config.json), inlined into `values.schema.json`.

To refresh it from upstream:
```bash
make schema-update
```

## Auth

Provider API keys are stored in a templated Secret and injected as env vars:

```bash
helm install opencode ./chart \
  --set auth.apiKeySecret.ANTHROPIC_API_KEY=sk-... \
  --set auth.basic.enabled=true \
  --set auth.basic.password=changeme
```

When `auth.basic.password` is set, the health probes automatically send the Basic-auth header so liveness/readiness/startup
checks pass. If you use `auth.basic.existingSecret` instead, the password isn't available at render time and the probes are omitted entirely. The chart warns you about this at install time.

To keep probes active, set `auth.basic.password` or exempt `/global/health` from authentication.

For production secrets, create your own Secret and set `auth.existingSecret`.

## Ingress

Disabled by default. Enable with a host and (optionally) cert-manager:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: opencode.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts: [opencode.example.com]
      secretName: opencode-tls
```

When exposing publicly, enable basic auth or implement your own auth proxy.
