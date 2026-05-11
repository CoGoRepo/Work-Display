# Kubernetes Network Check

## Diagnosis

- Primary issue: service routing fails but direct pod IP curl works. This often means the Service targetPort is wrong or does not match the port the app listens on. Current service port mapping: 80->9999.

## Status Summary

| Status | Count |
|---|---:|
| FAIL | 3 |
| INFO | 3 |
| PASS | 14 |
| SKIP | 3 |
| WARN | 1 |

## Failure Summary

| Layer | Check | Message |
|---|---|---|
| Pod-to-Service Networking Layer | service short name | http://wrong-port:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |
| Pod-to-Service Networking Layer | service FQDN | http://wrong-port.default.svc.cluster.local:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |
| Pod-to-Service Networking Layer | ClusterIP | http://10.96.65.4:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |

## Target

| Field | Value |
|---|---|
| Namespace | `default` |
| Service | `wrong-port` |
| Deployment | `wrong-port` |
| Timestamp | `2026-05-11T17:06:42.2775970-05:00` |
| KubeCommand | `kc` |
| DebugImage | `nicolaka/netshoot:latest` |
| Scheme | `http` |
| Path | `/` |
| ExpectedPort | `0` |

## Warnings

| Layer | Check | Message |
|---|---|---|
| Service Layer | targetPort metadata | Selected pods do not declare container ports. Kubernetes allows this, but the script cannot compare targetPort metadata. |

## Results By Layer

### Cluster Access

| Check | Status | Message |
|---|---|---|
| kubectl | PASS | kc is available. |
| namespace | PASS | Namespace 'default' exists. |

### Deployment Layer

| Check | Status | Message |
|---|---|---|
| replicas | PASS | Deployment 'wrong-port' has 1/1 available replica(s). |

### Pod Health Layer

| Check | Status | Message |
|---|---|---|
| pod selector | INFO | Using pod selector: app=wrong-port |
| pods exist | PASS | 1 pod(s) found. |
| running | PASS | 1/1 pod(s) are Running. |
| ready | PASS | 1/1 pod(s) are Ready. |
| container states | PASS | No CrashLoopBackOff/ImagePullBackOff-style waiting reasons detected. |

### Service Layer

| Check | Status | Message |
|---|---|---|
| service exists | PASS | Service 'wrong-port' exists. |
| service details | INFO | Type=ClusterIP; ClusterIP=10.96.65.4; Ports=80->9999/TCP; Selector=app=wrong-port |
| selected port | INFO | Testing service port 80 with targetPort 9999. |
| targetPort metadata | WARN | Selected pods do not declare container ports. Kubernetes allows this, but the script cannot compare targetPort metadata. |

### Endpoint Mapping Layer

| Check | Status | Message |
|---|---|---|
| endpoint slices | PASS | Ready endpoint IPs: 10.244.2.2 |
| pod to endpoint match | PASS | Selected pod IPs appear in ready EndpointSlices. |

### Debug Pod

| Check | Status | Message |
|---|---|---|
| debug pod ready | PASS | Temporary debug pod 'net-test' is Ready. |

### DNS Layer

| Check | Status | Message |
|---|---|---|
| resolve wrong-port | PASS | Debug pod resolved 'wrong-port'. |
| resolve wrong-port.default.svc.cluster.local | PASS | Debug pod resolved 'wrong-port.default.svc.cluster.local'. |

### Pod-to-Service Networking Layer

| Check | Status | Message |
|---|---|---|
| service short name | FAIL | http://wrong-port:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |
| service FQDN | FAIL | http://wrong-port.default.svc.cluster.local:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |
| ClusterIP | FAIL | http://10.96.65.4:80/ failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener. |

### Pod-to-Pod Networking Layer

| Check | Status | Message |
|---|---|---|
| curl 10.244.2.2 | PASS | http://10.244.2.2:80/ reachable from debug pod. HTTP status: 200 |

### NodePort / kube-proxy Layer

| Check | Status | Message |
|---|---|---|
| nodeport | SKIP | Service type is not NodePort/LoadBalancer. |

### Host-to-Cluster Layer

| Check | Status | Message |
|---|---|---|
| host nodeport | SKIP | Service type is not NodePort/LoadBalancer. |

### Optional Port-Forward Validation

| Check | Status | Message |
|---|---|---|
| port-forward | SKIP | Skipped. Add -TestPortForward to run this check. |
