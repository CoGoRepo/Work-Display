# KubeNetMods

KubeNetMods is an experimental PowerShell module for Kubernetes network and network-adjacent troubleshooting.

It grew out of the single-file `KubeNetChecker.ps1` script, but the goal is broader: give someone a structured way to answer, "Is this a Kubernetes networking problem, and where should I look first?"

The first public command is:

```powershell
Test-KubeNetService
```

The command focuses on one target Service and optionally one source namespace/pod. It walks through the path layer by layer: cluster access, nodes, CNI hints, DNS, Service, EndpointSlice, NetworkPolicy, Ingress, NodePort, LoadBalancer, source-to-target reachability, pod-side MTU/route snapshots, and events.

## Status

This is a prototype module. It is already useful for testing real scenarios, but some checks are intentionally heuristic.

The report separates three ideas:

- `FAIL`: a deterministic config problem or a runtime test failure.
- `WARN`: suspicious or risky configuration that may matter, but is not proven broken.
- `Diagnosis`: the highest-signal likely cause after filtering out downstream symptoms.

For example, a NetworkPolicy may statically appear to block traffic, but if the live source-to-target curl succeeds, the module leaves that as a warning instead of calling it the root diagnosis.

## Layout

```text
KubeNetMods/
  KubeNetMods.psd1
  KubeNetMods.psm1
  Public/
    Test-KubeNetService.ps1
  Private/
    KubeNetCore.ps1
  Reports/
    Export-KubeNetHtml.ps1
```

`KubeNetChecker.prototype.ps1` is the script copy used as the starting point. The module implementation lives in `Public`, `Private`, and `Reports`.

## Import

```powershell
Import-Module .\KubeNetMods.psd1 -Force
```

Use `-Verbose` on the command if you want to see the underlying `kubectl` commands.

## Quick Start

Check a Service in one namespace:

```powershell
Test-KubeNetService `
  -Namespace default `
  -ServiceName nginx
```

Save an HTML report:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -ExportHtml .\api-net.html
```

Save HTML and JSON:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -ExportHtml .\api-net.html `
  -ExportJson .\api-net.json
```

Run deeper optional checks:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -Deep `
  -ExportHtml .\api-deep.html
```

`-Deep` currently enables workload DNS checks, egress checks, Ingress checks, and LoadBalancer checks.

## What It Checks

Core target checks:

- `kubectl` access and namespace existence
- node readiness and common node network/pressure conditions
- kube-system CNI/CoreDNS/kube-proxy pod health
- CoreDNS service IP and Corefile sanity
- Service existence, type, ClusterIP, selector, ports, and `targetPort`
- selected pod health, readiness, image pull/crash states, and declared ports
- EndpointSlice ready addresses and endpoint ports
- recent warning events

Source-to-target checks:

- source namespace existence
- source pod selection by name or label selector
- source pod `/etc/resolv.conf`
- source pod DNS resolver path
- source-to-target FQDN resolution
- source-to-target curl against `service.namespace.svc.cluster.local`
- short-name DNS behavior from another namespace
- direct pod-IP curl from exec-capable debug/source pods
- source and target pod-side MTU/route snapshots when exec is available

Policy and routing checks:

- source egress NetworkPolicy analysis
- target ingress NetworkPolicy analysis
- DNS egress policy analysis, including NodeLocalDNS/link-local resolver cases
- CNI/provider guess and warning when NetworkPolicy objects exist but the CNI may not enforce them
- direct pod-IP results to help separate Service routing issues from pod/app reachability issues
- NodePort and host reachability
- optional `kubectl port-forward` validation

Ingress and external checks:

- Ingress objects pointing at the target Service
- Ingress backend Service port/name validation
- Ingress TLS secret existence
- IngressClass existence
- visible ingress/controller pod readiness hints
- explicit Ingress URL tests from the local host
- LoadBalancer service address/provider hints
- explicit external target tests

## Reading The Report

The HTML report is meant to be read top-down:

1. Start with `Diagnosis`.
2. Review `Failures`.
3. Review `Warnings`.
4. Use the detailed layer table if you need to understand why the module reached that conclusion.

Warnings do not always mean something is broken. They mean, "this is worth looking at."

Example: if a target ingress policy does not obviously allow the source namespace, but the live curl succeeds, the module keeps that as a warning and does not make it a diagnosis. In a local `kindnet` cluster, that can happen because NetworkPolicy objects exist but the CNI does not enforce them.

## Cross-Namespace Checks

Use `-SourceNamespace` when the real question is whether one namespace can reach a Service in another namespace.

Example: an app in `apps` needs to reach PostgreSQL in `database`.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

The module checks the target Service normally, then tests source-side DNS and reachability against:

```text
postgres.database.svc.cluster.local
```

If the FQDN works but the application still fails, check whether the app is using the short name `postgres` instead of `postgres.database` or the FQDN.

## Source Pod Checks

By default, source-to-target checks use a temporary debug pod in the source namespace.

To test from the actual application pod:

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -SourcePodSelector "app=api" `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

For a specific pod/container:

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -SourcePodName api-7f8d9c4d5b-x2p6q `
  -SourceContainer api `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

Source pod checks are especially useful for DNS and NetworkPolicy, because a generic debug pod may not have the same labels, DNS policy, service account, sidecars, or restrictions as the real workload.

## DNS Checks

Basic DNS checks happen from debug/source pods when exec is available.

Use `-TestPodDns` to inspect DNS from a target workload pod:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPodDns
```

Target a specific workload pod/container:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPodDns `
  -DnsPodName api-7f8d9c4d5b-x2p6q `
  -DnsContainer api
```

DNS-related cases the module can help identify:

- `dnsPolicy: Default` using node DNS instead of cluster DNS
- `hostNetwork` pods without `ClusterFirstWithHostNet`
- `dnsPolicy: None` with missing or unusual nameservers/searches
- missing search domains causing short service names to fail
- source pod can resolve short names but not the cross-namespace FQDN
- source pod uses NodeLocalDNS/link-local DNS but egress policy only allows CoreDNS pods

## NetworkPolicy Checks

The module reads actual NetworkPolicy objects and compares them to the selected source and target path.

It can flag:

- source pod is egress-isolated and no rule obviously allows the target Service/pods
- target pods are ingress-isolated and no rule obviously allows the source pod/namespace
- DNS egress appears blocked to the pod's runtime resolver
- NetworkPolicy exists but the detected CNI may not enforce it

These are static config checks plus runtime observations. A policy warning is not automatically a failure. If runtime curl succeeds, the warning stays as context.

## Ingress Checks

If Ingress objects exist and point at the target Service, the module checks them even if it cannot find controller pods.

Static Ingress checks still apply in managed clusters or RBAC-limited environments. Controller discovery is only a best-effort hint.

Ingress checks include:

- route host/path/backend discovery
- backend Service port/name exists
- TLS secret exists in the Ingress namespace
- referenced IngressClass exists
- Ingress status has an address
- visible ingress/controller pods are Ready, when discoverable

Explicit URL test:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestIngress `
  -IngressUrls https://api.example.com/health
```

Gateway API is not covered yet. A future Gateway layer should inspect `GatewayClass`, `Gateway`, `HTTPRoute`, `backendRefs`, listener conditions, certificate refs, and route attachment status.

## Egress Checks

Use `-TestEgress` to test outbound reachability from the source namespace or source pod.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace apps `
  -ServiceName api `
  -TestEgress `
  -EgressTargets https://kubernetes.default.svc,https://example.com
```

This is useful for finding issues around egress NetworkPolicy, DNS, NAT, proxies, firewall rules, or cloud security controls.

## LoadBalancer And External Checks

For `LoadBalancer` services:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName public-api `
  -TestLoadBalancer
```

The module inspects Kubernetes service status, annotations/provider hints, and any exposed load-balancer address.

You can also test explicit external URLs:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -ExternalTargets https://api.example.com/health
```

The module does not call AWS, Azure, or GCP APIs.

## Port-Forward Check

Use `-TestPortForward` to validate whether `kubectl port-forward` can reach the Service from the local host:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPortForward
```

If port-forward works but NodePort/Ingress/LoadBalancer fails, that narrows the problem toward external routing, ingress, node routing, firewall, or provider load-balancing rather than the pod itself.

## Cross-Cluster Notes

Kubernetes `ClusterIP` and service DNS are cluster-local. Cross-cluster checks cannot use `service.namespace.svc.cluster.local` unless the environment has service mesh, multi-cluster DNS, or custom forwarding.

For true cross-cluster validation, provide explicit external routes:

```powershell
Test-KubeNetService `
  -SourceContext dev-cluster `
  -SourceNamespace apps `
  -TargetContext prod-cluster `
  -Namespace database `
  -ServiceName postgres `
  -ExternalTargets https://postgres.example.internal
```

## Parameters

### Target

| Parameter | Default | Purpose |
|---|---:|---|
| `-Namespace` | `default` | Target Service namespace. |
| `-ServiceName` | `nginx` | Target Service name. |
| `-DeploymentName` | empty | Target Deployment name. Defaults to Service name when omitted. |
| `-ServicePort` | `0` | Service port to test. Uses the first Service port when omitted. |
| `-UrlScheme` | `http` | URL scheme for curl/HTTP checks. |
| `-Path` | `/` | HTTP path used for curl checks. |
| `-PodSelector` | empty | Override target pod selector. |
| `-TargetContext` | current | kubectl context for the target cluster. |

### Source

| Parameter | Default | Purpose |
|---|---:|---|
| `-SourceNamespace` | target namespace | Namespace to test from. |
| `-SourceContext` | target context | kubectl context for source checks. |
| `-SourcePodName` | empty | Actual source pod to exec into. |
| `-SourcePodSelector` | empty | Select a source pod by labels. |
| `-SourceContainer` | empty | Container name for source pod exec. |

### Debug Pods

| Parameter | Default | Purpose |
|---|---:|---|
| `-DebugImage` | `nicolaka/netshoot:latest` | Debug pod image. |
| `-DebugImagePullPolicy` | `IfNotPresent` | Pull policy for temporary debug pods. |
| `-DebugPodName` | `kubenetmods-debug` | Target namespace debug pod name. |
| `-SourceDebugPodName` | `kubenetmods-source-debug` | Source namespace debug pod name. |
| `-SkipDebugPod` | false | Skip checks that create/exec into debug pods. |

### Optional Tests

| Parameter | Default | Purpose |
|---|---:|---|
| `-TestPodDns` | false | Exec into target workload pod for DNS checks. |
| `-DnsPodName` | empty | Target workload pod for `-TestPodDns`. |
| `-DnsContainer` | empty | Container for target workload DNS exec. |
| `-TestEgress` | false | Test egress from source namespace/pod. |
| `-EgressTargets` | `https://kubernetes.default.svc` | URLs for egress checks. |
| `-TestIngress` | false | Test explicit Ingress URLs when supplied. Static Ingress discovery runs when Ingresses exist. |
| `-IngressUrls` | empty | Explicit Ingress URLs to test from local host. |
| `-TestLoadBalancer` | false | Inspect/test LoadBalancer service external paths. |
| `-ExternalTargets` | empty | Explicit external URLs to test from local host. |
| `-TestPortForward` | false | Run kubectl port-forward validation. |
| `-SkipNodePort` | false | Skip NodePort/host reachability checks. |
| `-Deep` | false | Enables several optional checks at once. |

### Output

| Parameter | Default | Purpose |
|---|---:|---|
| `-ExportJson` | empty | Save JSON report. |
| `-ExportHtml` | empty | Save HTML report. |
| `-PassThru` | false | Return report object. |
| `-Quiet` | false | Suppress console output. |
| `-Verbose` | false | Show kubectl commands. |

## Sample Reports

Sample HTML and JSON reports are included in [`examples/reports`](./examples/reports).

Useful examples:

- [`cross-namespace-smoke.html`](./examples/reports/cross-namespace-smoke.html): healthy cross-namespace service path
- [`dns-policy-nodelocal.html`](./examples/reports/dns-policy-nodelocal.html): source pod uses a NodeLocal/link-local resolver but policy only allows CoreDNS pods
- [`target-ingress-policy-block.html`](./examples/reports/target-ingress-policy-block.html): static target ingress policy warning, runtime curl passes because local CNI does not enforce policy
- [`ingress-misconfig.html`](./examples/reports/ingress-misconfig.html): deterministic Ingress config failures
- [`wrong-targetport-direct-pod.html`](./examples/reports/wrong-targetport-direct-pod.html): direct pod IP works, but Service routing fails because `targetPort` points at the wrong backend port

## Safety

The module is mostly read-only, but some checks create temporary debug pods or run `kubectl exec`.

Temporary debug pods are cleaned up automatically. If a run is interrupted, clean them up with:

```powershell
kubectl delete pod kubenetmods-debug -n <namespace> --ignore-not-found
kubectl delete pod kubenetmods-source-debug -n <namespace> --ignore-not-found
```

Use `-SkipDebugPod` for read-mostly inspection.

## Current Limitations

- Gateway API is not implemented yet.
- NetworkPolicy analysis is heuristic. It handles common selectors, namespace selectors, ipBlocks, and ports, but Kubernetes policy behavior can get more complex.
- CNI checks do not run provider-specific dataplane commands.
- kube-proxy checks are currently health/routing oriented, not a deep iptables/IPVS/eBPF inspection.
- MTU and route checks are snapshots from exec-capable pods using `ip -o link show` and `ip route show`. The module compares source/target pod `eth0` MTU values when both are available, but it does not yet perform path-MTU discovery, packet-size probing, node route-table inspection, or cloud route-table inspection.
- Cloud LoadBalancer checks inspect Kubernetes state and optional URLs only. They do not call cloud provider APIs.
- Cross-cluster service DNS is not assumed to work. Use explicit external targets, ingress, mesh, or provider-specific connectivity.
- HTTP checks focus on reachability. Auth failures or expected application responses are out of scope unless you choose a health endpoint that proves them.
- Edge-region/provider outages, such as only one country failing to reach an app, are outside the current Kubernetes-only scope unless they appear through explicit external URL tests.
