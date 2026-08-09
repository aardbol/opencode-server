# OpenCode Server Helm Chart

Hardened Helm chart for deploying the OpenCode server
(`opencode serve`, a headless AI coding-agent HTTP API on port 4096) into
Kubernetes. Pairs with the `ghcr.io/aardbol/opencode-server` image.

## Install

```bash
helm repo add opencode-server https://aardbol.github.io/opencode-server
helm install opencode opencode-server/opencode -n opencode --create-namespace
```

Or from this repo:

```bash
helm install opencode ./chart -n opencode --create-namespace
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
| `config.enabled` | bool | `true` | Render the opencode config ConfigMap. |
| `config.path` | string | `/home/opencode/opencode.jsonc` | Mount path for the config file. |
| `config.content` | object | `server` block | Body of `opencode.jsonc`. |
| `auth.basic.enabled` | bool | `false` | Enable HTTP basic auth. |
| `auth.basic.username` | string | `opencode` | Basic-auth username. |
| `auth.basic.password` | string | `""` | Basic-auth password (**set at install, not committed**). |
| `auth.basic.existingSecret` | string | `""` | Use a pre-created Secret for the password. |
| `auth.existingSecret` | string | `""` | Use a pre-created Secret for all auth. |
| `auth.apiKeySecret` | object | `{}` | Map of env var name → value (e.g. `ANTHROPIC_API_KEY`). |
| `service.type` | string | `ClusterIP` | Service type. |
| `service.port` | int | `4096` | Service port. |
| `ingress.enabled` | bool | `false` | Enable the Ingress resource. |
| `ingress.className` | string | `""` | Ingress class name. |
| `ingress.hosts` | list | `[]` | Ingress hosts/paths. |
| `ingress.tls` | list | `[]` | Ingress TLS config. |
| `ingress.certManagerIssuer` | string | `""` | cert-manager ClusterIssuer annotation. |
| `persistence.enabled` | bool | `false` | Provision a PVC for `/home/opencode`. |
| `persistence.size` | string | `1Gi` | PVC size. |
| `persistence.storageClass` | string | `""` | StorageClass (dynamic if empty). |
| `persistence.existingClaim` | string | `""` | Use an existing PVC. |
| `networkPolicy.enabled` | bool | `true` | Deploy a deny-all NetworkPolicy. |
| `networkPolicy.dnsNamespace` | string | `kube-system` | Namespace hosting kube-dns. |
| `networkPolicy.egress` | list | `[]` | Extra egress allowlist rules. |
| `resources` | object | see values | CPU/memory requests & limits. |
| `hpa.enabled` | bool | `false` | Enable HorizontalPodAutoscaler. |
| `pdb.enabled` | bool | `false` | Enable PodDisruptionBudget. |

## Config

The chart renders an `opencode.jsonc` ConfigMap from `config.content` and mounts
it read-only. `OPENCODE_CONFIG` is set to `config.path`. Example:

```yaml
config:
  content:
    server:
      port: 4096
      hostname: 0.0.0.0
      cors:
        - http://localhost:5173
```

## Auth

Provider API keys are stored in a templated Secret and injected as env vars:

```bash
helm install opencode ./chart \
  --set auth.apiKeySecret.ANTHROPIC_API_KEY=sk-... \
  --set auth.basic.enabled=true \
  --set auth.basic.password=changeme
```

For production secrets, create your own Secret and set `auth.existingSecret`.

## Ingress

Disabled by default. Enable with a host and (optionally) cert-manager:

```yaml
ingress:
  enabled: true
  className: nginx
  certManagerIssuer: letsencrypt-prod
  hosts:
    - host: opencode.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts: [opencode.example.com]
      secretName: opencode-tls
```

When exposing publicly, enable basic auth.

## Persistence

Enable to persist sessions/config across restarts:

```yaml
persistence:
  enabled: true
  size: 5Gi
```

## NetworkPolicy

By default a deny-all NetworkPolicy is applied. DNS egress to `kube-system` is
always allowed; add provider endpoints via `networkPolicy.egress`, e.g. to
allow Anthropic:

```yaml
networkPolicy:
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

## Upgrading

Chart version `0.1.0` tracks image appVersion `1.18.15`. Bump `image.tag` to
follow upstream OpenCode releases.
