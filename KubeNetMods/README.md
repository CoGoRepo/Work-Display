# KubeNetMods

KubeNetMods is an experimental PowerShell module for Kubernetes network and network-adjacent troubleshooting.

Its first public command is:

```powershell
Test-KubeNetService
```

The command starts with one target Kubernetes Service and walks the path around it: cluster access, nodes, DNS, Service, EndpointSlice, pods, NetworkPolicy, Ingress, NodePort, LoadBalancer, source-to-target reachability, pod-side MTU/route snapshots, and recent events.

The goal is not to replace observability platforms. The goal is to give an engineer a structured answer to:

```text
Is this actually a Kubernetes networking problem, and where should I look first?
```

## Current Status

This is a prototype module. It is usable for real troubleshooting, but some checks are intentionally heuristic.

Report statuses mean:

| Status | Meaning |
|---|---|
| `FAIL` | A deterministic config problem or runtime test failure. |
| `WARN` | Suspicious configuration that may matter, but is not proven broken. |
| `PASS` | The check succeeded. |
| `SKIP` | The check did not apply or was disabled. |
| `INFO` | Context collected for the report. |

The `Diagnosis` section is filtered to avoid blaming downstream symptoms when a clearer upstream issue exists.

## What It Can Do

Core Kubernetes checks:

- verify `kubectl` access and namespace existence
- inspect node readiness and common node pressure/network conditions
- inspect kube-system CNI, CoreDNS, and kube-proxy pod health
- inspect CoreDNS service IP and Corefile basics
- inspect Service type, ClusterIP, selector, ports, and `targetPort`
- inspect selected pod health, readiness, image pull/crash states, and declared ports
- inspect EndpointSlice ready addresses and endpoint ports
- surface recent warning events

Runtime path checks:

- test DNS and HTTP from temporary debug pods
- test from a real source workload pod by name or label selector
- test cross-namespace service FQDNs such as `postgres.database.svc.cluster.local`
- test direct pod-IP reachability to separate pod/app issues from Service routing issues
- test NodePort from inside the cluster and from the local host
- optionally test `kubectl port-forward`

DNS and policy checks:

- inspect source and target pod DNS settings
- read pod `/etc/resolv.conf` when exec is available
- detect common `dnsPolicy`, `dnsConfig`, and `hostNetwork` gotchas
- analyze source egress NetworkPolicies for the selected path
- analyze target ingress NetworkPolicies for the selected path
- analyze DNS egress policies, including NodeLocalDNS/link-local resolver cases
- warn when NetworkPolicy objects exist but the detected CNI may not enforce them

Ingress, LoadBalancer, and external checks:

- find Ingress objects pointing at the target Service
- validate Ingress backend service port/name references
- check Ingress TLS secret existence
- check IngressClass existence
- inspect visible ingress/controller pod readiness hints
- optionally test explicit Ingress URLs from the local host
- inspect LoadBalancer service addresses and provider hints
- optionally test explicit external URLs

Snapshot checks:

- collect pod-side interface MTUs with `ip -o link show`
- collect pod-side routes with `ip route show`
- compare source and target pod `eth0` MTU values when both are available

## What It Cannot Do Yet

- It does not inspect Gateway API resources yet.
- It does not deeply understand service mesh config such as Istio, Linkerd, or Consul.
- It does not run provider-specific CNI dataplane commands.
- It does not deeply inspect kube-proxy iptables, IPVS, or eBPF state.
- It does not perform path-MTU discovery, packet-size probing, or DF-bit testing.
- It does not inspect node route tables or cloud route tables.
- It does not call AWS, Azure, or GCP APIs.
- It does not prove country/region edge-provider outages unless they appear through explicit external URL tests.
- It does not validate application auth or business logic. HTTP checks focus on reachability.
- NetworkPolicy analysis is heuristic. Complex selectors or advanced CNI-specific behavior may still need human review.

## Safety

The module is mostly read-only, but some checks create temporary debug pods or run `kubectl exec`.

Temporary debug pods are cleaned up automatically. If a run is interrupted, clean them up with:

```powershell
kubectl delete pod kubenetmods-debug -n <namespace> --ignore-not-found
kubectl delete pod kubenetmods-source-debug -n <namespace> --ignore-not-found
```

Use `-SkipDebugPod` for read-mostly inspection.

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
| `-SkipDebugPod` | false | Skip checks that create or exec into debug pods. |

### Optional Checks

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
| `-TestPortForward` | false | Run `kubectl port-forward` validation. |
| `-SkipNodePort` | false | Skip NodePort/host reachability checks. |
| `-Deep` | false | Enables `-TestPodDns`, `-TestEgress`, `-TestIngress`, and `-TestLoadBalancer`. |

### Output

| Parameter | Default | Purpose |
|---|---:|---|
| `-ExportJson` | empty | Save JSON report. |
| `-ExportHtml` | empty | Save HTML report. |
| `-PassThru` | false | Return report object. |
| `-Quiet` | false | Suppress console output. |
| `-Verbose` | false | Show underlying `kubectl` commands. |

## Quick Start

Import the module from the module directory:

```powershell
Import-Module .\KubeNetMods.psd1 -Force
```

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

## Common Examples

### Cross-Namespace Service Path

Use `-SourceNamespace` when an app in one namespace must reach a Service in another namespace.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

The module tests the target Service and source-side DNS/reachability against:

```text
postgres.database.svc.cluster.local
```

### Test From The Real Source Pod

A temporary debug pod may not have the same labels, DNS policy, sidecars, service account, or NetworkPolicies as the real app. Use a source pod when that matters.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -SourcePodSelector "app=api" `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

Or target a specific pod/container:

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -SourcePodName api-7f8d9c4d5b-x2p6q `
  -SourceContainer api `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

### Target Workload DNS

Use `-TestPodDns` to exec into a selected target workload pod and inspect DNS from inside that pod.

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPodDns
```

Specific pod/container:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPodDns `
  -DnsPodName api-7f8d9c4d5b-x2p6q `
  -DnsContainer api
```

### Ingress URL

Static Ingress checks run when Ingress objects point at the target Service. Use `-TestIngress` and `-IngressUrls` to test a real URL from the local host.

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestIngress `
  -IngressUrls https://api.example.com/health
```

### Egress

Use `-TestEgress` to test outbound reachability from the source namespace or source pod.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace apps `
  -ServiceName api `
  -TestEgress `
  -EgressTargets https://kubernetes.default.svc,https://example.com
```

### LoadBalancer Or External URL

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName public-api `
  -TestLoadBalancer
```

You can also test explicit external targets:

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -ExternalTargets https://api.example.com/health
```

### Port-Forward

Use `-TestPortForward` to check whether `kubectl port-forward` can reach the Service from the local host.

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestPortForward
```

If port-forward works but NodePort, Ingress, or LoadBalancer fails, the problem is more likely outside the pod path.

### Cross-Cluster Note

Kubernetes `ClusterIP` and `service.namespace.svc.cluster.local` DNS are cluster-local. For true cross-cluster validation, provide explicit external routes.

```powershell
Test-KubeNetService `
  -SourceContext dev-cluster `
  -SourceNamespace apps `
  -TargetContext prod-cluster `
  -Namespace database `
  -ServiceName postgres `
  -ExternalTargets https://postgres.example.internal
```

## Reading The Report

The HTML report is meant to be read top-down:

1. Start with `Diagnosis`.
2. Review `Failures`.
3. Review `Warnings`.
4. Use the detailed layer table when you need evidence.

Warnings do not always mean something is broken. They mean the configuration is worth looking at.

Example: if a target ingress policy does not obviously allow the source namespace, but the live curl succeeds, the module keeps that as a warning instead of calling it the root diagnosis.

## Sample Reports

Sample HTML and JSON reports are included in [`examples/reports`](./examples/reports).

- [`cross-namespace-smoke.html`](./examples/reports/cross-namespace-smoke.html): healthy cross-namespace service path
- [`dns-policy-nodelocal.html`](./examples/reports/dns-policy-nodelocal.html): source pod uses a NodeLocal/link-local resolver but policy only allows CoreDNS pods
- [`target-ingress-policy-block.html`](./examples/reports/target-ingress-policy-block.html): static target ingress policy warning, runtime curl passes because local CNI does not enforce policy
- [`ingress-misconfig.html`](./examples/reports/ingress-misconfig.html): deterministic Ingress config failures
- [`wrong-targetport-direct-pod.html`](./examples/reports/wrong-targetport-direct-pod.html): direct pod IP works, but Service routing fails because `targetPort` points at the wrong backend port

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
  examples/
    reports/
```

The `.psm1` is the module loader. Public commands live in `Public`, helper functions live in `Private`, report exporters live in `Reports`, and example output lives in `examples/reports`.
