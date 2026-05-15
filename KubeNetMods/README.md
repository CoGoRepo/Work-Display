# KubeNetMods

KubeNetMods is an experimental PowerShell module for Kubernetes network and network-adjacent troubleshooting.

It starts with a target Kubernetes Service and works outward through the path around it: cluster access, nodes, DNS, Service, EndpointSlice, pods, NetworkPolicy, Ingress, NodePort, LoadBalancer, source-to-target reachability, pod-side MTU/route snapshots, and recent events.

The goal is simple:

```text
Is this actually a Kubernetes networking problem, and where should I look first?
```

## Commands

| Command | Purpose |
|---|---|
| `Test-KubeNetService` | Main diagnostic command for a Kubernetes Service/network path. |
| `ConvertTo-KubeNetAlert` | Normalize alert JSON into a provider-neutral KubeNet alert object. |
| `ConvertTo-KubeNetServiceParameters` | Convert a normalized alert into a visible `Test-KubeNetService` parameter plan. |
| `Invoke-KubeNetAlertTriage` | Normalize, classify, plan, and optionally run KubeNet diagnostics from an alert payload. |

## Current Status

This is a prototype module. It is usable for real troubleshooting, but some checks are intentionally heuristic.

Report statuses:

| Status | Meaning |
|---|---|
| `FAIL` | A deterministic config problem or runtime test failure. |
| `WARN` | Suspicious configuration that may matter, but is not proven broken. |
| `PASS` | The check succeeded. |
| `SKIP` | The check did not apply or was disabled. |
| `INFO` | Context collected for the report. |

The `Diagnosis` section is filtered so downstream symptoms do not drown out the clearest likely cause.

## What It Can Do

| Area | Checks |
|---|---|
| Cluster access | `kubectl` access, namespace existence, node readiness, common node pressure/network conditions. |
| Core networking | CNI/CoreDNS/kube-proxy pod health, CoreDNS service IP, Corefile basics. |
| Service path | Service type, ClusterIP, selector, ports, `targetPort`, selected pod health, EndpointSlice readiness. |
| Runtime reachability | DNS and HTTP from debug pods, source workload pods, direct pod IP, Service FQDN, NodePort, optional port-forward. |
| DNS | Pod DNS settings, `/etc/resolv.conf`, `dnsPolicy`, `dnsConfig`, `hostNetwork`, NodeLocalDNS/link-local resolver cases. |
| NetworkPolicy | Source egress, target ingress, DNS egress, and CNI enforcement hints. |
| Ingress | Ingress routes to the Service, backend port/name, TLS secret, IngressClass, controller pod hints, optional URL tests. |
| LoadBalancer/external | LoadBalancer addresses, provider hints, optional explicit external URL tests. |
| Snapshots | Pod-side MTU and route snapshots, plus source/target `eth0` MTU comparison when available. |
| Alerts | Best-effort alert normalization, scope classification, parameter planning, and optional triage run. |

## What It Cannot Do Yet

- It does not inspect Gateway API resources.
- It does not deeply understand service mesh config such as Istio, Linkerd, or Consul.
- It does not run provider-specific CNI dataplane commands.
- It does not deeply inspect kube-proxy iptables, IPVS, or eBPF state.
- It does not perform path-MTU discovery, packet-size probing, or DF-bit testing.
- It does not inspect node route tables or cloud route tables.
- It does not call AWS, Azure, or GCP APIs.
- It does not prove country/region edge-provider outages unless they appear through explicit external URL tests.
- It does not validate application auth or business logic. HTTP checks focus on reachability.
- NetworkPolicy analysis is heuristic. Complex selectors or CNI-specific behavior may still need human review.
- Alert normalization is best-effort because alert platforms and teams use different label/tag names.

## Safety

The module is mostly read-only, but some checks create temporary debug pods or run `kubectl exec`.

Temporary debug pods are cleaned up automatically. If a run is interrupted:

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
| `-UrlPath` | `/` | HTTP path used for curl checks. |
| `-TargetPodSelector` | empty | Override target pod selector. |
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
| `-TargetDebugPodName` | `kubenetmods-debug` | Target namespace debug pod name. |
| `-SourceDebugPodName` | `kubenetmods-source-debug` | Source namespace debug pod name. |
| `-SkipDebugPod` | false | Skip checks that create or exec into debug pods. |

### Optional Checks

| Parameter | Default | Purpose |
|---|---:|---|
| `-TestTargetPodDns` | false | Exec into target workload pod for DNS checks. |
| `-TargetDnsPodName` | empty | Target workload pod for `-TestTargetPodDns`. |
| `-TargetDnsContainer` | empty | Container for target workload DNS exec. |
| `-TestEgress` | false | Test egress from source namespace/pod. |
| `-EgressUrls` | `https://kubernetes.default.svc` | URLs for egress checks. |
| `-TestIngress` | false | Test explicit Ingress URLs when supplied. Static Ingress discovery runs when Ingresses exist. |
| `-IngressUrls` | empty | Explicit Ingress URLs to test from local host. |
| `-TestLoadBalancer` | false | Inspect/test LoadBalancer service external paths. |
| `-ExternalUrls` | empty | Explicit external URLs to test from local host. |
| `-TestPortForward` | false | Run `kubectl port-forward` validation. |
| `-SkipNodePort` | false | Skip NodePort/host reachability checks. |
| `-Deep` | false | Enables `-TestTargetPodDns`, `-TestEgress`, `-TestIngress`, and `-TestLoadBalancer`. |

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

Check a Service:

```powershell
Test-KubeNetService `
  -Namespace default `
  -ServiceName nginx
```

Save HTML and JSON reports:

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

## Alert Payload Triage

Alert handling is intentionally separate from the main diagnostic command:

```text
raw alert JSON -> normalized alert -> scope classification -> parameter plan -> optional run
```

Normalize an alert:

```powershell
ConvertTo-KubeNetAlert `
  -Provider Grafana `
  -Path .\examples\alerts\grafana-ingress-backend.json
```

Preview the inferred parameters:

```powershell
ConvertTo-KubeNetServiceParameters `
  -Provider Alertmanager `
  -Path .\examples\alerts\alertmanager-dns-timeout.json
```

Run triage only when the alert is in scope and has enough metadata:

```powershell
Invoke-KubeNetAlertTriage `
  -Provider Alertmanager `
  -Path .\examples\alerts\alertmanager-dns-timeout.json `
  -ExportHtml .\alert-triage.html
```

Preview an out-of-scope alert:

```powershell
Invoke-KubeNetAlertTriage `
  -Provider Datadog `
  -Path .\examples\alerts\datadog-http-401.json `
  -PreviewOnly
```

The triage wrapper will not run by default when an alert is out of scope or missing the target `Namespace`/`ServiceName`. Use `-Force` only when you intentionally want to run with the inferred parameters anyway.

## Common Examples

### Cross-Namespace Service Path

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

This tests the target Service and source-side DNS/reachability against:

```text
postgres.database.svc.cluster.local
```

### Test From The Real Source Pod

Use a real source pod when labels, DNS policy, sidecars, service accounts, or NetworkPolicies may differ from a generic debug pod.

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -SourcePodSelector "app=api" `
  -Namespace database `
  -ServiceName postgres `
  -ServicePort 5432
```

Specific pod/container:

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

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestTargetPodDns `
  -TargetDnsPodName api-7f8d9c4d5b-x2p6q `
  -TargetDnsContainer api
```

### Ingress URL

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -TestIngress `
  -IngressUrls https://api.example.com/health
```

### Egress

```powershell
Test-KubeNetService `
  -SourceNamespace apps `
  -Namespace apps `
  -ServiceName api `
  -TestEgress `
  -EgressUrls https://kubernetes.default.svc,https://example.com
```

### LoadBalancer Or External URL

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName public-api `
  -TestLoadBalancer
```

```powershell
Test-KubeNetService `
  -Namespace apps `
  -ServiceName api `
  -ExternalUrls https://api.example.com/health
```

### Port-Forward

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
  -ExternalUrls https://postgres.example.internal
```

## Reading The Report

Read the HTML report from the top down:

1. Start with `Diagnosis`.
2. Review `Failures`.
3. Review `Warnings`.
4. Use the detailed layer table when you need evidence.

Warnings do not always mean something is broken. They mean the configuration is worth reviewing.

## Samples

Sample HTML and JSON reports are in [`examples/reports`](./examples/reports).

| Report | Scenario |
|---|---|
| [`cross-namespace-smoke.html`](./examples/reports/cross-namespace-smoke.html) | Healthy cross-namespace service path. |
| [`dns-policy-nodelocal.html`](./examples/reports/dns-policy-nodelocal.html) | Source pod uses NodeLocalDNS/link-local resolver, but policy only allows CoreDNS pods. |
| [`target-ingress-policy-block.html`](./examples/reports/target-ingress-policy-block.html) | Static target ingress policy warning while runtime curl passes. |
| [`ingress-misconfig.html`](./examples/reports/ingress-misconfig.html) | Deterministic Ingress config failures. |
| [`wrong-targetport-direct-pod.html`](./examples/reports/wrong-targetport-direct-pod.html) | Direct pod IP works, but Service routing fails because `targetPort` is wrong. |

Sample alert payloads are in [`examples/alerts`](./examples/alerts).

| Alert | Scenario |
|---|---|
| [`alertmanager-dns-timeout.json`](./examples/alerts/alertmanager-dns-timeout.json) | Network-relevant DNS timeout with enough metadata to run. |
| [`grafana-ingress-backend.json`](./examples/alerts/grafana-ingress-backend.json) | Network-relevant Ingress/backend alert. |
| [`datadog-http-401.json`](./examples/alerts/datadog-http-401.json) | Out-of-scope application-auth alert. |
| [`generic-missing-service.json`](./examples/alerts/generic-missing-service.json) | Network-looking alert missing target Service metadata. |

## Layout

```text
KubeNetMods/
  KubeNetMods.psd1
  KubeNetMods.psm1
  Public/
  Private/
  Reports/
  examples/
    alerts/
    reports/
```

The `.psm1` is the module loader. Public commands live in `Public`, helper functions live in `Private`, report exporters live in `Reports`, and example payloads/reports live in `examples`.
