# KC Net Checker

`KubeNetChecker.ps1` is a PowerShell Kubernetes network troubleshooting helper.

It walks through a Kubernetes service path layer by layer and tries to show where the problem most likely lives instead of only saying "curl failed."

It was originally built for a Windows host using Docker Desktop Kubernetes and a `kc` alias for `kubectl`, but it can also run in other environments with PowerShell and `kubectl`.

## What It Checks

The script checks these layers:

1. Cluster access
2. Deployment health
3. Pod health
4. Service configuration and port/targetPort mapping
5. EndpointSlice mapping
6. DNS from inside the cluster
7. Pod-to-service networking
8. Pod-to-pod networking
9. NodePort/kube-proxy behavior from inside the cluster
10. Host-to-NodePort behavior from the machine running the script
11. Optional port-forward validation

At the end, it prints a summary and a diagnosis section.

Example diagnosis:

```text
Internal service routing is healthy, but the Windows host cannot reach NodePort.
Likely Docker Desktop/WSL/VM networking, firewall, or host routing.
```

Another example:

```text
Primary issue: Service targetPort mismatch.
Service routing fails, direct pod IP curl works, and targetPort metadata does not match selected pod container ports.
Current service port mapping: 80->9999.
```

## Requirements

On the machine running the script:

- PowerShell 5.1+ or PowerShell 7+
- `kubectl` installed and in `PATH`
- Optional: a `kc` alias/function for `kubectl`
- Valid kubeconfig/context
- Access to the target Kubernetes cluster

In the cluster:

- Permission to read namespaces, deployments, pods, services, EndpointSlices, and nodes
- Permission to create/delete a temporary debug pod if using DNS/curl tests
- Permission to exec into the temporary debug pod
- Ability to pull the debug image, or access to an internal debug image

The script prefers `kc` if it exists. If not, it falls back to `kubectl`.

## Quick Start

Default check:

```powershell
.\KubeNetChecker.ps1
```

The default values are:

```powershell
-Namespace default
-ServiceName nginx
-Scheme http
-Path /
```

Check a specific service:

```powershell
.\KubeNetChecker.ps1 -ServiceName my-service -Namespace apps
```

Check a service and deployment:

```powershell
.\KubeNetChecker.ps1 `
  -DeploymentName my-api `
  -ServiceName my-api `
  -Namespace apps
```

Check a specific port and health path:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-api `
  -Namespace apps `
  -ExpectedPort 8080 `
  -Path /health
```

## Safe First Run in Production

In a real production environment, you may not want to create a temporary debug pod right away.

Start with read-mostly checks:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-service `
  -Namespace prod `
  -SkipDebugPod `
  -SkipNodePort `
  -SkipPortForward
```

This checks cluster access, deployment, pods, service configuration, and EndpointSlices without launching the debug pod.

If the team allows a temporary diagnostic pod:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-service `
  -Namespace prod `
  -DebugImage registry.company.local/tools/netshoot:v0.13.0
```

## Debug Image

The default debug image is:

```text
nicolaka/netshoot:latest
```

`netshoot` is useful because it includes tools like `curl`, `nslookup`, `dig`, and other network troubleshooting utilities.

For controlled environments, use an approved internal image:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-service `
  -Namespace prod `
  -DebugImage registry.company.local/tools/netshoot:v0.13.0
```

The script does not require Docker Hub. Kubernetes pulls whatever image string you provide.

Examples:

```powershell
-DebugImage harbor.company.local/platform/netshoot:v0.13.0
-DebugImage registry.example.com/tools/curl:8.5.0
-DebugImage registry1.dso.mil/ironbank/approved/debug-image:tag
```

If the image cannot be pulled, the debug pod checks will fail and the script will point that out.

## Parameters

| Parameter | Default | Description |
|---|---:|---|
| `-Namespace` | `default` | Kubernetes namespace to test. |
| `-DeploymentName` | empty | Deployment to check. If omitted, the script tries a deployment with the same name as the service. |
| `-ServiceName` | `nginx` | Service to troubleshoot. |
| `-ExpectedPort` | `0` | Expected service port clients should hit. If omitted, the first service port is used. |
| `-Scheme` | `http` | URL scheme for curl tests. Use `https` for HTTPS services. |
| `-Path` | `/` | HTTP path to test. |
| `-PodSelector` | empty | Optional label selector for pods, such as `app=my-api`. |
| `-DebugImage` | `nicolaka/netshoot:latest` | Debug pod image. Can be internal/private. |
| `-TestPodName` | `net-test` | Name of the temporary debug pod. |
| `-TimeoutSec` | `5` | Timeout for curl/local HTTP checks. |
| `-KubeCommand` | empty | Override command path/name. Example: `kubectl`, `kc`, or full path. |
| `-SkipDebugPod` | false | Skip checks that require a temporary pod. |
| `-SkipNodePort` | false | Skip NodePort and host-to-NodePort tests. |
| `-SkipPortForward` | false | Skip optional port-forward logic. |
| `-TestPortForward` | false | Run the optional port-forward test. |
| `-ExportJson` | empty | Write a JSON report to the specified path. |
| `-ExportMarkdown` | empty | Write a Markdown report to the specified path. |
| `-Verbose` | false | Show underlying kubectl commands and extra detail. |

## Common Examples

### Basic nginx test

```powershell
.\KubeNetChecker.ps1
```

### Test a service in another namespace

```powershell
.\KubeNetChecker.ps1 -ServiceName web -Namespace frontend
```

### Test a service with a deployment name

```powershell
.\KubeNetChecker.ps1 `
  -DeploymentName web `
  -ServiceName web `
  -Namespace frontend
```

### Test an API health endpoint

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName orders-api `
  -Namespace apps `
  -ExpectedPort 8080 `
  -Path /healthz
```

### Test a specific service port

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName orders-api `
  -Namespace apps `
  -ExpectedPort 8080
```

`-ExpectedPort` means "the service port clients should use." The script reads the actual `targetPort` from the Kubernetes Service.

If the expected port is not exposed by the service, the script reports that as the primary issue and skips curl checks that would only create noise.

### Test HTTPS

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName secure-api `
  -Namespace apps `
  -Scheme https `
  -ExpectedPort 443 `
  -Path /health
```

### Use a specific pod selector

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api-service `
  -Namespace apps `
  -PodSelector "app=api,tier=backend"
```

### Use kubectl instead of kc

```powershell
.\KubeNetChecker.ps1 `
  -KubeCommand kubectl `
  -ServiceName api `
  -Namespace apps
```

### Use a full kubectl path

```powershell
.\KubeNetChecker.ps1 `
  -KubeCommand "C:\Tools\kubectl.exe" `
  -ServiceName api `
  -Namespace apps
```

### Skip debug pod checks

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace prod `
  -SkipDebugPod
```

This skips:

- DNS tests from inside the cluster
- Curl service name from debug pod
- Curl ClusterIP from debug pod
- Curl pod IPs from debug pod
- Curl NodeIP:NodePort from debug pod

### Skip NodePort checks

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace prod `
  -SkipNodePort
```

Useful when the service is not exposed by NodePort or when the cluster is cloud/load-balancer based.

### Run optional port-forward test

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace apps `
  -TestPortForward
```

This starts a temporary `kubectl port-forward`, tests localhost access, and stops the port-forward process.

### Export JSON and Markdown reports

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace apps `
  -ExportJson .\api-net-check.json `
  -ExportMarkdown .\api-net-check.md
```

### Verbose mode

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace apps `
  -Verbose
```

Verbose mode prints the underlying `kubectl`/`kc` commands being run.

## Example Output

```text
== Deployment Layer ==
   Validates whether the expected deployment exists and has available replicas.
[PASS] Deployment 'nginx' has 3/3 available replica(s).

== Pod Health Layer ==
   Finds pods behind the service/deployment and checks phase, readiness, and common waiting reasons.
[PASS] 3 pod(s) found.
[PASS] 3/3 pod(s) are Running.
[PASS] 3/3 pod(s) are Ready.
[PASS] No CrashLoopBackOff/ImagePullBackOff-style waiting reasons detected.

== Endpoint Mapping Layer ==
   Uses EndpointSlice, the modern replacement for deprecated Endpoints, to verify service-to-pod mapping.
[PASS] Ready endpoint IPs: 10.244.1.2, 10.244.2.2, 10.244.3.2

== Diagnosis ==
 - Internal service routing is healthy, but the Windows host cannot reach NodePort.
   Likely Docker Desktop/WSL/VM networking, firewall, or host routing.
```

## How To Read The Layers

### Cluster Access

This confirms that the script can run `kubectl`/`kc` and read the target namespace.

If this fails, it is usually:

- kubeconfig problem
- wrong context
- expired credentials
- missing VPN/network path
- insufficient RBAC

### Deployment Layer

Checks whether the deployment exists and whether desired replicas are available.

If this fails, the issue is usually not service networking yet. Check:

- deployment exists
- replica count
- rollout status
- scheduling
- image pulls
- pod startup

Useful commands:

```powershell
kc get deploy -n <namespace>
kc describe deploy <deployment> -n <namespace>
kc rollout status deploy/<deployment> -n <namespace>
```

### Pod Health Layer

Checks whether pods exist, are Running, are Ready, and whether common problem states are present.

Common problem states:

- `CrashLoopBackOff`
- `ImagePullBackOff`
- `ErrImagePull`
- `CreateContainerConfigError`
- `RunContainerError`

If pods are not Ready, Kubernetes services may not send traffic to them.

Useful commands:

```powershell
kc get pods -n <namespace> -o wide
kc describe pod <pod> -n <namespace>
kc logs <pod> -n <namespace>
```

### Service Layer

Checks whether the service exists and prints:

- service type
- ClusterIP
- ports
- NodePorts
- selectors
- selected service port and targetPort
- whether the targetPort matches declared container port metadata, when available

If the service selector is wrong, the service will not map to the intended pods.

If the service exposes one port but forwards to a bad `targetPort`, service traffic can fail even when the pod itself is healthy.

Example:

```text
Service port mapping: 80->9999
Pod responds directly on: 80
```

In that case, the script should identify a likely Service `targetPort` mismatch.

Note: Kubernetes container ports are metadata. An app can listen on a port even if the pod spec does not declare it, so a targetPort metadata mismatch by itself is a warning. A metadata mismatch plus failed service curl plus successful direct pod curl is treated as a stronger diagnosis.

Useful commands:

```powershell
kc get svc <service> -n <namespace> -o wide
kc describe svc <service> -n <namespace>
kc get pods -n <namespace> -o yaml
```

### Endpoint Mapping Layer

Checks EndpointSlices for ready backend pod IPs.

Modern Kubernetes uses EndpointSlices instead of the older Endpoints API.

If pods are healthy but EndpointSlices are empty, likely causes include:

- service selector does not match pod labels
- pods are not Ready
- EndpointSlice controller issue
- wrong namespace/service

Useful commands:

```powershell
kc get endpointslice -n <namespace>
kc get endpointslice -n <namespace> -l kubernetes.io/service-name=<service>
```

### DNS Layer

Creates a temporary debug pod and tests:

- short service name
- full service FQDN

Examples:

```text
my-service
my-service.my-namespace.svc.cluster.local
```

If DNS fails, likely causes include:

- CoreDNS problem
- wrong service name
- wrong namespace
- cluster DNS policy issue

Useful commands:

```powershell
kc get pods -n kube-system
kc logs -n kube-system -l k8s-app=kube-dns
```

### Pod-to-Service Networking Layer

From the debug pod, the script curls:

- service short name
- service FQDN
- ClusterIP

This helps distinguish:

- DNS failure
- service routing failure
- application not listening
- NetworkPolicy blocking traffic

If service name fails but ClusterIP works, suspect DNS.

If service name and ClusterIP both fail, suspect service routing, NetworkPolicy, kube-proxy, or the app listener.

### Pod-to-Pod Networking Layer

From the debug pod, the script curls backend pod IPs directly.

If pod IP curl fails while pods are Ready, likely causes include:

- CNI/overlay networking problem
- NetworkPolicy blocking pod-to-pod traffic
- app is not listening on the expected port/interface
- wrong expected port

If pod IP curl works but service/ClusterIP curl fails, likely causes include:

- wrong Service `targetPort`
- service routing/kube-proxy problem
- NetworkPolicy affecting service path differently than direct pod path

The most common beginner mistake is a Service that exposes the right port but forwards to the wrong targetPort.

### NodePort / kube-proxy Layer

From inside the cluster, the script curls:

```text
NodeIP:NodePort
```

If this fails, likely causes include:

- kube-proxy issue
- node firewall
- NodePort not allocated
- service routing issue
- cluster/node network issue

### Host-to-Cluster Layer

From the machine running the script, it curls:

```text
NodeIP:NodePort
```

In Docker Desktop, kind, minikube, and WSL-based setups, failure here may be normal depending on how node networks are exposed.

If internal cluster tests pass but host-to-NodePort fails, likely causes include:

- Docker Desktop networking
- WSL networking
- VM NAT
- local firewall
- private node IPs not reachable from your machine
- cloud security groups/routes

### Optional Port-Forward Validation

Port-forward is useful when NodePort or host routing is failing.

If port-forward works but NodePort fails, the app and service are probably okay. The issue is likely exposure/routing outside the cluster.

Run it with:

```powershell
.\KubeNetChecker.ps1 -ServiceName api -Namespace apps -TestPortForward
```

## Docker Desktop Notes

Docker Desktop and local multi-node clusters can behave differently from real production clusters.

It is common for these to pass:

- pod health
- EndpointSlice checks
- DNS checks
- service curl
- ClusterIP curl
- pod IP curl
- inside-cluster NodePort curl

But fail:

- Windows host to `NodeIP:NodePort`

That usually means the Kubernetes service is healthy, but the node IPs are not directly reachable from Windows.

In that case, test whether Docker Desktop exposes the service another way, or use port-forward:

```powershell
kc port-forward svc/nginx 8080:80 -n default
```

Then browse:

```text
http://localhost:8080
```

## Production Notes

In production, be careful with the debug pod.

Before running full checks, ask whether it is okay to create a temporary diagnostic pod in the target namespace.

Recommended first run:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-service `
  -Namespace prod `
  -SkipDebugPod `
  -SkipNodePort `
  -SkipPortForward
```

Then run full diagnostics only if allowed:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName my-service `
  -Namespace prod `
  -DebugImage registry.company.local/tools/netshoot:v0.13.0
```

Production environments may block:

- public image pulls
- `latest` tags
- ad hoc pod creation
- exec into pods
- node read access
- NodePort access
- port-forward

That does not mean the script is broken. It means the cluster is enforcing policy.

## Cross-Platform Usage

The script is PowerShell, so it can run on:

- Windows PowerShell
- PowerShell 7 on Windows
- PowerShell 7 on Linux
- PowerShell 7 on macOS

On Linux/macOS:

```bash
pwsh ./KubeNetChecker.ps1 -ServiceName nginx -Namespace default
```

The script uses `Start-Process` in a cross-platform way for the optional port-forward test.

## Troubleshooting The Script

### It cannot find kc or kubectl

Install `kubectl`, add it to PATH, or pass a command:

```powershell
.\KubeNetChecker.ps1 -KubeCommand kubectl
```

### The debug pod cannot be created

Possible causes:

- RBAC does not allow pod creation
- admission policy blocks the pod
- image cannot be pulled
- `latest` tags are blocked
- namespace has strict Pod Security settings

Try an approved internal image:

```powershell
.\KubeNetChecker.ps1 `
  -ServiceName api `
  -Namespace prod `
  -DebugImage registry.company.local/tools/netshoot:v0.13.0
```

Or skip debug pod checks:

```powershell
.\KubeNetChecker.ps1 -ServiceName api -Namespace prod -SkipDebugPod
```

### EndpointSlice check fails

Check selector labels:

```powershell
kc get svc <service> -n <namespace> -o yaml
kc get pods -n <namespace> --show-labels
kc get endpointslice -n <namespace> -l kubernetes.io/service-name=<service>
```

### DNS fails but ClusterIP works

Likely DNS/CoreDNS issue.

Check:

```powershell
kc get pods -n kube-system
kc logs -n kube-system -l k8s-app=kube-dns
```

### Pod IP works but service name/ClusterIP fails

Likely service or kube-proxy/service routing issue.

Check:

```powershell
kc describe svc <service> -n <namespace>
kc get endpointslice -n <namespace> -l kubernetes.io/service-name=<service>
```

### Service works inside cluster but not from host

Likely host/network exposure issue.

Common with:

- Docker Desktop
- WSL
- kind
- minikube
- private cloud node networks
- firewalls/security groups

Try:

```powershell
.\KubeNetChecker.ps1 -ServiceName api -Namespace apps -TestPortForward
```

## Exit Codes

The script exits with:

- `0` when no failures were found
- `1` when one or more failures were found, or a hard blocker occurred

Warnings and skipped checks do not automatically cause failure.

## Notes

This script is meant for troubleshooting and learning. It does not fix cluster networking. It helps identify which layer is likely broken so you know where to look next.

For locked-down environments, always follow your organization's change control and security policies before launching diagnostic pods.
