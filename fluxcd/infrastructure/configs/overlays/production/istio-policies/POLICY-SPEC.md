# Istio AuthorizationPolicy Spec

Canonical reference for the cluster's Istio zero-trust policy architecture.
When reality diverges from this spec, fix reality — not the spec.

## Trust Model

- **Default deny** in all namespaces (empty-spec AuthorizationPolicy)
- **DENY `default` SA** cluster-wide (`spiffe://*/sa/default`)
- Workload access must be authorized by **explicit source identity or source IP constraints**; labels only opt workloads into reusable policy contracts — labels themselves are not trust signals

## Identity Model (Ambient Mesh)

In this cluster's ambient mesh configuration, the original caller identity is
preserved through HBONE. This is an **operational model for this environment** —
the invariant that matters is the consequence below, not a universal law about
all Istio traffic shapes.

**Consequence:** Pods reaching services via gateway must be authorized at BOTH:
1. The gateway (to enter)
2. The backend (to be served)

A pod monitored through a gateway needs BOTH `ingress: "true"` AND `probe: "true"`.

## Policy Layers

Evaluation order: DENY policies first, then ALLOW (OR composition).

### Layer 1 — Infrastructure Contracts (base, all namespaces)

**Path:** `fluxcd/infrastructure/configs/base/istio-policies/`
**Ownership:** platform

| Policy | Selector | Principal | Purpose |
|---|---|---|---|
| `allow-gatus` | `probe: "true"` | `gossip-stone/gatus` | Health check probes |
| `allow-prometheus` | `metrics: "true"` | `gossip-stone/alloy` | Prometheus scrape |
| `allow-dns` | all pods | kube-dns | DNS resolution |
| `allow-cnpg-operator` | CNPG pods | operator SA | PostgreSQL management |
| `allow-mariadb-operator` | MariaDB pods | operator SA | MariaDB management |
| `allow-redis-operator` | Redis pods | operator SA | Redis management |

### Layer 2 — Gateway Ingress (generated, per namespace)

**Path:** `fluxcd/infrastructure/configs/overlays/production/istio-policies/<ns>/allow-gateway-ingress-*.yaml`
**Generator:** `hack/gen-gateway-ingress-policies.sh`
**Ownership:** generator (do NOT hand-edit)

- Selector: `policy.prplanit.com/ingress: "true"`
- Principal: gateway SA (e.g., `optcp-ingress-internal/phloem-ingress-gateway-istio`)
- Ports: derived from HTTPRoute backendRefs → Service targetPort resolution

**Important distinction — gateway entry vs backend authorization:**
- For **external LAN clients** (non-mesh): traffic arrives at the gateway without a SPIFFE identity. The gateway proxies it, and the backend sees the gateway SA as the source. The gateway-ingress policy is sufficient.
- For **in-mesh callers traversing a gateway** (e.g., Gatus): ambient mesh preserves the original workload identity through HBONE. The backend sees the **original caller identity**, not the gateway SA. These callers must be authorized at the backend independently — typically via Layer 1 contracts (e.g., `probe: "true"` for Gatus).

The gateway-ingress policy authorizes **who may enter** the gateway. It does NOT guarantee the backend will serve the request — that depends on whether the backend has a matching ALLOW for the caller's identity.

### Layer 3 — LoadBalancer Ingress (hand-written, per service)

**Path:** `fluxcd/infrastructure/configs/overlays/production/istio-policies/<ns>/allow-*-loadbalancer.yaml`
**Ownership:** manual

- Selector: app-specific (e.g., `app: adguard`)
- Single rule: RFC1918 `ipBlocks` — no `notIpBlocks`, no principal rules
- Cilium owns anti-hairpin (pod CIDR exclusion at L3/L4)
- pfSense owns LAN segment access control

**Why no `notIpBlocks` or principal rules on LB policies:**
Pod→LB traffic is ztunnel passthrough (no SPIFFE identity visible to the destination).
Principal-based rules do not apply because there is no identity to match against.
`notIpBlocks` would block legitimate in-cluster monitoring (Gatus) with no alternative
enforcement path. Cilium handles pod CIDR exclusion at L3/L4 where it is effective.

### Layer 4 — Service-to-Service (hand-written, per relationship)

**Ownership:** manual

- Principal-based, explicit SA
- Port-scoped
- Examples: `allow-harbor-core-to-harbor-registry`, `allow-zigbee2mqtt-to-mosquitto`

## Label Contract

| Label | Meaning | Authorizes |
|---|---|---|
| `policy.prplanit.com/ingress: "true"` | Receives traffic from gateways | Gateway SA principals |
| `policy.prplanit.com/probe: "true"` | Accepts health check probes | `gossip-stone/gatus` |
| `policy.prplanit.com/metrics: "true"` | Exposes Prometheus metrics | `gossip-stone/alloy` |

## Hardening Principles

1. **One app role = one SA.** Service accounts are part of the trust boundary. Never share SAs across apps unless there is a reviewed reason. Istio principal precision collapses silently when SAs are over-shared.

2. **Gateway-exposed backends must be safe even if the gateway is compromised or misconfigured.** Backend authorization must never rely solely on "traffic came from the gateway." The gateway-entry / backend-authorization split exists for this reason.

3. **Defense in depth between Cilium and Istio.** Cilium is the packet-path containment layer (L3/L4). Istio is the workload-identity authorization layer (L7). Neither should assume the other caught everything. Both layers must independently prevent unauthorized access.

4. **Egress is the primary post-compromise abuse surface.** Most weaponization is egress-shaped (exfiltration, beaconing, scanning, callback). See Cilium POLICY-SPEC.md for the egress classification model.

## Anti-Patterns

- **Never use `notPrincipals`** — use `ipBlocks`/`notIpBlocks` for negative source matching
- **Never use namespace-wide breakglass** (`namespaces: [X]` as source)
- **Never allow `default` SA**
- **Never hand-edit generated files** — modify the generator
- **Never create one-off policies** when a label + existing base policy would work

## When to Revise Policy vs App

1. Pod denied access it legitimately needs → **check labels first**
2. Label present but still denied → **check base policy port list**
3. Port list insufficient → **expand base policy, not create new policy**
4. No existing pattern fits → **update this spec first, then implement**
