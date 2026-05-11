<#
.SYNOPSIS
    Beginner-friendly Kubernetes network troubleshooting helper for PowerShell.

.DESCRIPTION
    Tests Kubernetes networking layer-by-layer and points at the likely failure
    domain. Built for Windows hosts, Docker Desktop/local clusters, and modern
    Kubernetes versions that prefer EndpointSlice over deprecated Endpoints.

    The script is read-mostly, but DNS/curl tests create one temporary debug pod
    unless those checks are skipped.

.EXAMPLE
    .\KubeNetChecker.ps1

.EXAMPLE
    .\KubeNetChecker.ps1 -DeploymentName nginx -ServiceName nginx -Namespace default

.EXAMPLE
    .\KubeNetChecker.ps1 -ServiceName api -Namespace apps -ExpectedPort 8080 -Path /health

.EXAMPLE
    .\KubeNetChecker.ps1 -ServiceName api -Namespace apps -SkipDebugPod -SkipPortForward

.EXAMPLE
    .\KubeNetChecker.ps1 -ServiceName api -Namespace apps -ExportJson .\net-report.json -ExportMarkdown .\net-report.md -ExportHtml .\net-report.html
#>

[CmdletBinding()]
param(
    [string]$Namespace = "default",
    [string]$DeploymentName = "",
    [string]$ServiceName = "nginx",
    [int]$ExpectedPort = 0,
    [string]$Scheme = "http",
    [string]$Path = "/",
    [string]$PodSelector = "",
    [string]$DebugImage = "nicolaka/netshoot:latest",
    [string]$TestPodName = "net-test",
    [int]$TimeoutSec = 5,
    [string]$KubeCommand = "",
    [switch]$SkipDebugPod,
    [switch]$SkipNodePort,
    [switch]$SkipPortForward,
    [switch]$TestPortForward,
    [string]$ExportJson = "",
    [string]$ExportMarkdown = "",
    [string]$ExportHtml = ""
)

$ErrorActionPreference = "Stop"
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:Diagnoses = [System.Collections.Generic.List[string]]::new()
$script:DebugPodCreated = $false
$script:DebugPodReady = $false
$script:Kubectl = $null

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-Explain {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor DarkGray
}

function Add-Result {
    param(
        [string]$Layer,
        [string]$Check,
        [ValidateSet("PASS", "FAIL", "WARN", "SKIP", "INFO")]
        [string]$Status,
        [string]$Message,
        [object]$Data = $null
    )

    $script:Results.Add([PSCustomObject]@{
        Layer   = $Layer
        Check   = $Check
        Status  = $Status
        Message = $Message
        Data    = $Data
    }) | Out-Null

    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        "SKIP" { "DarkYellow" }
        default { "Gray" }
    }

    Write-Host ("[{0}] " -f $Status) -ForegroundColor $color -NoNewline
    Write-Host $Message
}

function Add-Diagnosis {
    param([string]$Text)
    if (-not [string]::IsNullOrWhiteSpace($Text) -and -not $script:Diagnoses.Contains($Text)) {
        $script:Diagnoses.Add($Text) | Out-Null
    }
}

function Invoke-Kube {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Verbose ("kc {0}" -f ($Arguments -join " "))

    $stderrFile = [System.IO.Path]::GetTempFileName()
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $script:Kubectl @Arguments 2> $stderrFile
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference

        $stderr = ""
        if (Test-Path -LiteralPath $stderrFile) {
            $stderrRaw = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
            if ($null -ne $stderrRaw) {
                $stderr = $stderrRaw.Trim()
            }
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    $text = (($output | Out-String).Trim())

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $message = @($text, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        throw ($message -join "`n")
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $output
        Text     = $text
        Stderr   = $stderr
    }
}

function ConvertFrom-KubeJson {
    param([string[]]$Arguments)

    $result = Invoke-Kube -Arguments ($Arguments + @("-o", "json"))
    if ([string]::IsNullOrWhiteSpace($result.Text)) {
        return $null
    }

    $result.Text | ConvertFrom-Json
}

function Resolve-KubeCommand {
    param([string]$PreferredCommand)

    if (-not [string]::IsNullOrWhiteSpace($PreferredCommand)) {
        return $PreferredCommand
    }

    if (Get-Command kc -ErrorAction SilentlyContinue) {
        return "kc"
    }

    if (Get-Command kubectl -ErrorAction SilentlyContinue) {
        return "kubectl"
    }

    throw "Could not find 'kc' or 'kubectl' in PATH. Pass -KubeCommand if you use a different wrapper."
}

function Join-LabelSelector {
    param([object]$Selector)

    if ($null -eq $Selector) {
        return ""
    }

    $parts = @()
    foreach ($property in $Selector.PSObject.Properties) {
        $parts += "$($property.Name)=$($property.Value)"
    }

    $parts -join ","
}

function Get-CheckPort {
    param([object]$Service)

    if ($ExpectedPort -gt 0) {
        return $ExpectedPort
    }

    if ($Service -and $Service.spec.ports.Count -gt 0) {
        return [int]$Service.spec.ports[0].port
    }

    return 80
}

function Get-UrlPath {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return "/"
    }
    if ($Path.StartsWith("/")) {
        return $Path
    }
    return "/$Path"
}

function Get-ServiceUrls {
    param([object]$Service)

    $port = Get-CheckPort -Service $Service
    $urlPath = Get-UrlPath
    $clusterIp = $Service.spec.clusterIP
    $fqdn = "$ServiceName.$Namespace.svc.cluster.local"

    [PSCustomObject]@{
        Port      = $port
        ShortName = "$Scheme`://$ServiceName`:$port$urlPath"
        Fqdn      = "$Scheme`://$fqdn`:$port$urlPath"
        ClusterIp = if ($clusterIp -and $clusterIp -ne "None") { "$Scheme`://$clusterIp`:$port$urlPath" } else { "" }
    }
}

function Get-ServicePortSelection {
    param([object]$Service)

    if (-not $Service -or $Service.spec.ports.Count -eq 0) {
        return $null
    }

    $ports = @($Service.spec.ports)
    if ($ExpectedPort -gt 0) {
        $match = $ports | Where-Object { [int]$_.port -eq $ExpectedPort } | Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    return ($ports | Select-Object -First 1)
}

function Get-DeclaredContainerPorts {
    param([object[]]$Pods)

    $ports = @()
    foreach ($pod in @($Pods)) {
        foreach ($container in @($pod.spec.containers)) {
            if ($null -eq $container.ports) {
                continue
            }
            foreach ($port in @($container.ports)) {
                if ($null -eq $port -or $null -eq $port.containerPort) {
                    continue
                }
                $ports += [PSCustomObject]@{
                    Pod           = $pod.metadata.name
                    Container     = $container.name
                    Name          = $port.name
                    ContainerPort = $port.containerPort
                    Protocol      = $port.protocol
                }
            }
        }
    }
    $ports
}

function Test-TargetPortMatchesDeclaredPorts {
    param(
        [object]$SelectedServicePort,
        [object[]]$DeclaredPorts
    )

    if (-not $SelectedServicePort) {
        return [PSCustomObject]@{ Status = "Unknown"; Message = "No service port was selected."; TargetPort = $null }
    }

    $targetPort = $SelectedServicePort.targetPort
    if ($null -eq $targetPort) {
        $targetPort = $SelectedServicePort.port
    }

    if ($DeclaredPorts.Count -eq 0) {
        return [PSCustomObject]@{
            Status     = "NoDeclaredPorts"
            Message    = "Selected pods do not declare container ports. Kubernetes allows this, but the script cannot compare targetPort metadata."
            TargetPort = $targetPort
        }
    }

    $targetText = [string]$targetPort
    if ($targetText -match "^\d+$") {
        $matches = @($DeclaredPorts | Where-Object { [int]$_.ContainerPort -eq [int]$targetText })
        if ($matches.Count -gt 0) {
            return [PSCustomObject]@{
                Status     = "Match"
                Message    = "Service targetPort $targetText matches declared container port(s): $((@($matches | ForEach-Object { "$($_.Pod)/$($_.Container):$($_.ContainerPort)" }) | Sort-Object -Unique) -join ', ')"
                TargetPort = $targetPort
            }
        }

        $declared = (@($DeclaredPorts | ForEach-Object { "$($_.Pod)/$($_.Container):$($_.ContainerPort)" }) | Sort-Object -Unique) -join ", "
        return [PSCustomObject]@{
            Status     = "Mismatch"
            Message    = "Service targetPort $targetText does not match any declared container port. Declared ports: $declared"
            TargetPort = $targetPort
        }
    }

    $nameMatches = @($DeclaredPorts | Where-Object { $_.Name -eq $targetText })
    if ($nameMatches.Count -gt 0) {
        return [PSCustomObject]@{
            Status     = "Match"
            Message    = "Service named targetPort '$targetText' resolves to declared container port(s): $((@($nameMatches | ForEach-Object { "$($_.Pod)/$($_.Container):$($_.Name)=$($_.ContainerPort)" }) | Sort-Object -Unique) -join ', ')"
            TargetPort = $targetPort
        }
    }

    $declaredNames = (@($DeclaredPorts | Where-Object { $_.Name } | ForEach-Object { "$($_.Pod)/$($_.Container):$($_.Name)=$($_.ContainerPort)" }) | Sort-Object -Unique) -join ", "
    if ([string]::IsNullOrWhiteSpace($declaredNames)) {
        $declaredNames = "(none)"
    }

    [PSCustomObject]@{
        Status     = "Mismatch"
        Message    = "Service named targetPort '$targetText' does not match any declared container port name. Declared named ports: $declaredNames"
        TargetPort = $targetPort
    }
}

function Get-HttpStatusFromText {
    param([string]$Text)

    $match = [regex]::Match($Text, "HTTP_STATUS=(?<status>[0-9]{3})")
    if ($match.Success) {
        return $match.Groups["status"].Value
    }
    return "unknown"
}

function Test-LocalHttp {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -UseBasicParsing
        return [PSCustomObject]@{ Ok = $true; StatusCode = [int]$response.StatusCode; Error = "" }
    } catch {
        $statusCode = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        return [PSCustomObject]@{ Ok = $false; StatusCode = $statusCode; Error = $_.Exception.Message }
    }
}

function Ensure-DebugPod {
    if ($SkipDebugPod) {
        Add-Result -Layer "Debug Pod" -Check "debug pod" -Status "SKIP" -Message "Skipped by -SkipDebugPod."
        return $false
    }

    if ($script:DebugPodReady) {
        return $true
    }

    Write-Explain "Creating one temporary debug pod for DNS and network tests. It is removed at the end."
    Invoke-Kube -Arguments @("delete", "pod", $TestPodName, "-n", $Namespace, "--ignore-not-found=true", "--wait=true") -AllowFailure | Out-Null

    $run = Invoke-Kube -Arguments @(
        "run", $TestPodName,
        "--image=$DebugImage",
        "-n", $Namespace,
        "--restart=Never",
        "--command", "--",
        "sleep", "3600"
    ) -AllowFailure

    if ($run.ExitCode -ne 0) {
        Add-Result -Layer "Debug Pod" -Check "create debug pod" -Status "FAIL" -Message "Could not create debug pod '$TestPodName'. Check RBAC, image policy, or image pull access."
        Add-Diagnosis "The script could not create a debug pod, so DNS and inside-cluster network checks could not run. This is usually RBAC, image pull policy, or namespace policy."
        return $false
    }

    $script:DebugPodCreated = $true

    $wait = Invoke-Kube -Arguments @(
        "wait", "pod/$TestPodName",
        "-n", $Namespace,
        "--for=condition=Ready",
        "--timeout=$($TimeoutSec * 6)s"
    ) -AllowFailure

    if ($wait.ExitCode -ne 0) {
        Add-Result -Layer "Debug Pod" -Check "debug pod ready" -Status "FAIL" -Message "Debug pod was created but did not become Ready. Check image pulls, admission policy, or node scheduling."
        Add-Diagnosis "The debug pod did not become Ready, so the script could not prove DNS or service routing from inside the cluster."
        return $false
    }

    $script:DebugPodReady = $true
    Add-Result -Layer "Debug Pod" -Check "debug pod ready" -Status "PASS" -Message "Temporary debug pod '$TestPodName' is Ready."
    return $true
}

function Invoke-InDebugPod {
    param([string]$Command)

    Invoke-Kube -Arguments @("exec", "-n", $Namespace, $TestPodName, "--", "sh", "-c", $Command) -AllowFailure
}

function Remove-DebugPod {
    if ($script:DebugPodCreated) {
        Write-Verbose "Cleaning up debug pod '$TestPodName'."
        Invoke-Kube -Arguments @("delete", "pod", $TestPodName, "-n", $Namespace, "--ignore-not-found=true", "--wait=false") -AllowFailure | Out-Null
    }
}

function Get-SelectedPods {
    param(
        [object]$Service,
        [object]$Deployment
    )

    $selector = $PodSelector
    if ([string]::IsNullOrWhiteSpace($selector) -and $Service) {
        $selector = Join-LabelSelector -Selector $Service.spec.selector
    }
    if ([string]::IsNullOrWhiteSpace($selector) -and $Deployment) {
        $selector = Join-LabelSelector -Selector $Deployment.spec.selector.matchLabels
    }

    $args = @("get", "pods", "-n", $Namespace)
    if (-not [string]::IsNullOrWhiteSpace($selector)) {
        $args += @("-l", $selector)
    }

    [PSCustomObject]@{
        Selector = $selector
        Pods     = ConvertFrom-KubeJson -Arguments $args
    }
}

try {
    $script:Kubectl = Resolve-KubeCommand -PreferredCommand $KubeCommand
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$exitCode = 0
$service = $null
$deployment = $null
$podData = $null
$podIps = @()
$endpointIps = @()
$nodeIps = @()
$nodePorts = @()
$inClusterServiceOk = $false
$hostNodePortFailures = 0
$hostNodePortPasses = 0
$selectedPodCount = 0
$readyPodCount = 0
$runningPodCount = 0
$containerProblemReasons = @()
$deploymentHealthy = $false
$serviceCurlFailures = 0
$podIpCurlPasses = 0
$declaredContainerPorts = @()
$selectedServicePort = $null
$targetPortAnalysis = $null
$expectedPortMissing = $false

try {
    Write-Host "Kubernetes network checker" -ForegroundColor White
    Write-Host "Command:    $script:Kubectl" -ForegroundColor DarkGray
    Write-Host "Namespace:  $Namespace" -ForegroundColor DarkGray
    Write-Host "Service:    $ServiceName" -ForegroundColor DarkGray
    if ($DeploymentName) { Write-Host "Deployment: $DeploymentName" -ForegroundColor DarkGray }
    Write-Host "Debug pod:  $TestPodName ($DebugImage)" -ForegroundColor DarkGray

    Write-Section "Cluster Access"
    Write-Explain "Validates that kubectl can run and that the target namespace exists."
    try {
        $clientVersion = Invoke-Kube -Arguments @("version", "--client=true") -AllowFailure
        if ($clientVersion.ExitCode -eq 0) {
            Add-Result -Layer "Cluster Access" -Check "kubectl" -Status "PASS" -Message "$script:Kubectl is available."
        } else {
            Add-Result -Layer "Cluster Access" -Check "kubectl" -Status "WARN" -Message "$script:Kubectl responded, but version check returned a warning."
        }

        Invoke-Kube -Arguments @("get", "namespace", $Namespace) | Out-Null
        Add-Result -Layer "Cluster Access" -Check "namespace" -Status "PASS" -Message "Namespace '$Namespace' exists."
    } catch {
        Add-Result -Layer "Cluster Access" -Check "cluster" -Status "FAIL" -Message $_.Exception.Message
        Add-Diagnosis "Cannot continue until kubectl can access the cluster and namespace."
        throw
    }

    try {
        $service = ConvertFrom-KubeJson -Arguments @("get", "svc", $ServiceName, "-n", $Namespace)
    } catch {
        $service = $null
    }

    Write-Section "Deployment Layer"
    Write-Explain "Validates whether the expected deployment exists and has available replicas."
    if ([string]::IsNullOrWhiteSpace($DeploymentName)) {
        $candidate = $ServiceName
        $candidateDeploy = Invoke-Kube -Arguments @("get", "deployment", $candidate, "-n", $Namespace, "-o", "json") -AllowFailure
        if ($candidateDeploy.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidateDeploy.Text)) {
            $DeploymentName = $candidate
            $deployment = $candidateDeploy.Text | ConvertFrom-Json
            Add-Result -Layer "Deployment Layer" -Check "deployment inferred" -Status "INFO" -Message "No -DeploymentName was provided; found deployment '$DeploymentName'."
        } else {
            Add-Result -Layer "Deployment Layer" -Check "deployment" -Status "SKIP" -Message "No -DeploymentName provided and no deployment named '$ServiceName' was found."
        }
    } else {
        $deployResult = Invoke-Kube -Arguments @("get", "deployment", $DeploymentName, "-n", $Namespace, "-o", "json") -AllowFailure
        if ($deployResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($deployResult.Text)) {
            $deployment = $deployResult.Text | ConvertFrom-Json
        } else {
            Add-Result -Layer "Deployment Layer" -Check "deployment exists" -Status "FAIL" -Message "Deployment '$DeploymentName' does not exist in namespace '$Namespace'."
            Add-Diagnosis "The deployment is missing. This is an application/workload issue before networking."
        }
    }

    if ($deployment) {
        $desired = 1
        if ($null -ne $deployment.spec.replicas) { $desired = [int]$deployment.spec.replicas }

        $available = 0
        if ($null -ne $deployment.status.availableReplicas) { $available = [int]$deployment.status.availableReplicas }

        $ready = 0
        if ($null -ne $deployment.status.readyReplicas) { $ready = [int]$deployment.status.readyReplicas }
        if ($available -ge $desired -and $ready -ge $desired) {
            $deploymentHealthy = $true
            Add-Result -Layer "Deployment Layer" -Check "replicas" -Status "PASS" -Message "Deployment '$DeploymentName' has $available/$desired available replica(s)."
        } else {
            Add-Result -Layer "Deployment Layer" -Check "replicas" -Status "FAIL" -Message "Deployment '$DeploymentName' has $available/$desired available replica(s) and $ready/$desired ready replica(s)."
        }
    }

    Write-Section "Pod Health Layer"
    Write-Explain "Finds pods behind the service/deployment and checks phase, readiness, and common waiting reasons."
    try {
        $podData = Get-SelectedPods -Service $service -Deployment $deployment
        if ([string]::IsNullOrWhiteSpace($podData.Selector)) {
            Add-Result -Layer "Pod Health Layer" -Check "pod selector" -Status "WARN" -Message "No pod selector was available. Showing all namespace pods can be misleading."
        } else {
            Add-Result -Layer "Pod Health Layer" -Check "pod selector" -Status "INFO" -Message "Using pod selector: $($podData.Selector)"
        }

        $wideArgs = @("get", "pods", "-n", $Namespace, "-o", "wide")
        if (-not [string]::IsNullOrWhiteSpace($podData.Selector)) {
            $wideArgs += @("-l", $podData.Selector)
        }
        Invoke-Kube -Arguments $wideArgs | Select-Object -ExpandProperty Output | Write-Host

        $pods = @($podData.Pods.items)
        $selectedPodCount = $pods.Count
        if ($pods.Count -eq 0) {
            Add-Result -Layer "Pod Health Layer" -Check "pods exist" -Status "FAIL" -Message "No pods found for the selected labels."
            if ($deploymentHealthy -and $service -and -not [string]::IsNullOrWhiteSpace((Join-LabelSelector -Selector $service.spec.selector))) {
                Add-Diagnosis "Primary issue: service selector mismatch. The deployment appears healthy, but the service selector does not match any pods. Compare the service selector with the pod labels."
            } else {
                Add-Diagnosis "No pods matched the selector. The service selector/deployment labels may be wrong, or the workload has not created pods."
            }
        } else {
            Add-Result -Layer "Pod Health Layer" -Check "pods exist" -Status "PASS" -Message "$($pods.Count) pod(s) found."
        }

        $running = 0
        $readyCount = 0
        $badReasons = @()

        foreach ($pod in $pods) {
            if ($pod.status.phase -eq "Running") { $running++ }
            $readyCondition = $pod.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -First 1
            if ($readyCondition.status -eq "True") { $readyCount++ }

            foreach ($containerStatus in @($pod.status.containerStatuses + $pod.status.initContainerStatuses)) {
                if ($containerStatus.state.waiting.reason) {
                    $reason = $containerStatus.state.waiting.reason
                    $badReasons += "$($pod.metadata.name):$($containerStatus.name)=$reason"
                    $containerProblemReasons += $reason
                }
                if ($containerStatus.lastState.terminated.reason) {
                    $reason = $containerStatus.lastState.terminated.reason
                    $badReasons += "$($pod.metadata.name):$($containerStatus.name)=last:$reason"
                    $containerProblemReasons += $reason
                }
            }

            if ($pod.status.podIP) {
                $podIps += $pod.status.podIP
            }
        }

        $declaredContainerPorts = @(Get-DeclaredContainerPorts -Pods $pods)

        if ($pods.Count -gt 0) {
            $runningPodCount = $running
            $readyPodCount = $readyCount

            if ($running -eq $pods.Count) {
                Add-Result -Layer "Pod Health Layer" -Check "running" -Status "PASS" -Message "$running/$($pods.Count) pod(s) are Running."
            } else {
                Add-Result -Layer "Pod Health Layer" -Check "running" -Status "FAIL" -Message "$running/$($pods.Count) pod(s) are Running."
            }

            if ($readyCount -eq $pods.Count) {
                Add-Result -Layer "Pod Health Layer" -Check "ready" -Status "PASS" -Message "$readyCount/$($pods.Count) pod(s) are Ready."
            } else {
                Add-Result -Layer "Pod Health Layer" -Check "ready" -Status "FAIL" -Message "$readyCount/$($pods.Count) pod(s) are Ready."
            }
        }

        if ($badReasons.Count -gt 0) {
            Add-Result -Layer "Pod Health Layer" -Check "container states" -Status "FAIL" -Message "Problem states detected: $($badReasons -join '; ')"
            $uniqueReasons = @($containerProblemReasons | Sort-Object -Unique)
            if ($uniqueReasons -contains "ImagePullBackOff" -or $uniqueReasons -contains "ErrImagePull") {
                Add-Diagnosis "Primary issue: image pull failure detected ($($uniqueReasons -join ', ')). Check the image name/tag, registry access, imagePullSecrets, and whether the registry allows the cluster to pull it."
            } elseif ($uniqueReasons -contains "CrashLoopBackOff") {
                Add-Diagnosis "Primary issue: container is crashing (CrashLoopBackOff). Check the container command, application logs, config, secrets, and readiness/startup behavior before debugging networking."
            } elseif ($uniqueReasons.Count -gt 0) {
                Add-Diagnosis "Primary issue: container state problem detected ($($uniqueReasons -join ', ')). Fix pod/container health before debugging networking."
            } else {
                Add-Diagnosis "Primary issue: container waiting/terminated states were detected. Check image pulls, crashes, commands, probes, and app logs."
            }
        } elseif ($selectedPodCount -gt 0 -and $readyPodCount -lt $selectedPodCount) {
            Add-Diagnosis "Primary issue: pods are not Ready. Services normally avoid routing to unready pods, so fix readiness/application health first."
        } elseif ($deployment -and $available -lt $desired) {
            Add-Diagnosis "Primary issue: deployment replicas are not available. Fix scheduling or workload health before chasing service networking."
        } elseif ($pods.Count -gt 0) {
            Add-Result -Layer "Pod Health Layer" -Check "container states" -Status "PASS" -Message "No CrashLoopBackOff/ImagePullBackOff-style waiting reasons detected."
        }
    } catch {
        Add-Result -Layer "Pod Health Layer" -Check "pod inspection" -Status "WARN" -Message "Could not inspect pods: $($_.Exception.Message)"
    }

    Write-Section "Service Layer"
    Write-Explain "Checks service type, ClusterIP, NodePort, and selector labels."
    if ($service) {
        $selectedServicePort = Get-ServicePortSelection -Service $service
        $ports = @($service.spec.ports | ForEach-Object {
            $nodePortText = if ($_.nodePort) { " nodePort=$($_.nodePort)" } else { "" }
            "$($_.port)->$($_.targetPort)/$($_.protocol)$nodePortText"
        }) -join ", "
        $selectorText = Join-LabelSelector -Selector $service.spec.selector
        if ([string]::IsNullOrWhiteSpace($selectorText)) { $selectorText = "(none)" }

        Add-Result -Layer "Service Layer" -Check "service exists" -Status "PASS" -Message "Service '$ServiceName' exists."
        Add-Result -Layer "Service Layer" -Check "service details" -Status "INFO" -Message "Type=$($service.spec.type); ClusterIP=$($service.spec.clusterIP); Ports=$ports; Selector=$selectorText"

        if ($selectedServicePort) {
            Add-Result -Layer "Service Layer" -Check "selected port" -Status "INFO" -Message "Testing service port $($selectedServicePort.port) with targetPort $($selectedServicePort.targetPort)."
            $targetPortAnalysis = Test-TargetPortMatchesDeclaredPorts -SelectedServicePort $selectedServicePort -DeclaredPorts $declaredContainerPorts
            if ($targetPortAnalysis.Status -eq "Match") {
                Add-Result -Layer "Service Layer" -Check "targetPort metadata" -Status "PASS" -Message $targetPortAnalysis.Message
            } elseif ($targetPortAnalysis.Status -eq "NoDeclaredPorts") {
                Add-Result -Layer "Service Layer" -Check "targetPort metadata" -Status "WARN" -Message $targetPortAnalysis.Message
            } elseif ($targetPortAnalysis.Status -eq "Mismatch") {
                Add-Result -Layer "Service Layer" -Check "targetPort metadata" -Status "WARN" -Message $targetPortAnalysis.Message
            }
        }

        if ($ExpectedPort -gt 0) {
            $matchingPort = @($service.spec.ports | Where-Object { [int]$_.port -eq $ExpectedPort })
            if ($matchingPort.Count -gt 0) {
                Add-Result -Layer "Service Layer" -Check "expected port" -Status "PASS" -Message "Expected port $ExpectedPort exists on the service."
            } else {
                $expectedPortMissing = $true
                Add-Result -Layer "Service Layer" -Check "expected port" -Status "FAIL" -Message "Expected port $ExpectedPort was not found on the service."
                Add-Diagnosis "Primary issue: the service does not expose expected port $ExpectedPort. Check the service port definition or rerun with the port the service actually exposes."
            }
        }
    } else {
        Add-Result -Layer "Service Layer" -Check "service exists" -Status "FAIL" -Message "Service '$ServiceName' does not exist in namespace '$Namespace'."
        Add-Diagnosis "The service is missing. Create/fix the Service before debugging DNS, endpoints, or NodePort."
    }

    Write-Section "Endpoint Mapping Layer"
    Write-Explain "Uses EndpointSlice, the modern replacement for deprecated Endpoints, to verify service-to-pod mapping."
    if ($service) {
        try {
            $slices = ConvertFrom-KubeJson -Arguments @("get", "endpointslice", "-n", $Namespace, "-l", "kubernetes.io/service-name=$ServiceName")
            foreach ($slice in @($slices.items)) {
                foreach ($endpoint in @($slice.endpoints)) {
                    $isReady = $true
                    if ($null -ne $endpoint.conditions.ready) {
                        $isReady = [bool]$endpoint.conditions.ready
                    }
                    foreach ($address in @($endpoint.addresses)) {
                        if ($isReady) {
                            $endpointIps += $address
                        }
                    }
                }
            }

            $endpointIps = @($endpointIps | Sort-Object -Unique)
            if ($endpointIps.Count -eq 0) {
                Add-Result -Layer "Endpoint Mapping Layer" -Check "endpoint slices" -Status "FAIL" -Message "No ready EndpointSlice addresses found for service '$ServiceName'."
                if ($selectedPodCount -gt 0 -and $readyPodCount -eq $selectedPodCount) {
                    Add-Diagnosis "Pods are Ready but the service has no ready endpoints. Likely service selector mismatch or EndpointSlice/controller issue."
                }
            } else {
                Add-Result -Layer "Endpoint Mapping Layer" -Check "endpoint slices" -Status "PASS" -Message "Ready endpoint IPs: $($endpointIps -join ', ')"
            }

            if ($podIps.Count -gt 0 -and $endpointIps.Count -gt 0) {
                $missing = @($podIps | Where-Object { $_ -notin $endpointIps })
                if ($missing.Count -eq 0) {
                    Add-Result -Layer "Endpoint Mapping Layer" -Check "pod to endpoint match" -Status "PASS" -Message "Selected pod IPs appear in ready EndpointSlices."
                } else {
                    Add-Result -Layer "Endpoint Mapping Layer" -Check "pod to endpoint match" -Status "WARN" -Message "Some selected pod IPs are not ready endpoints: $($missing -join ', ')"
                }
            }
        } catch {
            Add-Result -Layer "Endpoint Mapping Layer" -Check "endpoint slices" -Status "FAIL" -Message "Could not read EndpointSlices: $($_.Exception.Message)"
        }
    } else {
        Add-Result -Layer "Endpoint Mapping Layer" -Check "endpoint slices" -Status "SKIP" -Message "Skipped because the service does not exist."
    }

    Write-Section "DNS Layer"
    Write-Explain "Tests Kubernetes service discovery from a temporary pod using short name and FQDN."
    $debugReady = Ensure-DebugPod
    if ($debugReady -and $service) {
        $names = @($ServiceName, "$ServiceName.$Namespace.svc.cluster.local")
        foreach ($name in $names) {
            $dns = Invoke-InDebugPod -Command "nslookup $name"
            if ($dns.ExitCode -eq 0) {
                Add-Result -Layer "DNS Layer" -Check "resolve $name" -Status "PASS" -Message "Debug pod resolved '$name'."
            } else {
                Add-Result -Layer "DNS Layer" -Check "resolve $name" -Status "FAIL" -Message "Debug pod could not resolve '$name'. Likely CoreDNS or service discovery issue."
                Add-Diagnosis "DNS resolution failed from inside the cluster. Check CoreDNS, service name/namespace, and cluster DNS policy."
                if ($dns.Text) { Write-Host $dns.Text -ForegroundColor DarkGray }
            }
        }
    } elseif (-not $service) {
        Add-Result -Layer "DNS Layer" -Check "dns tests" -Status "SKIP" -Message "Skipped because the service does not exist."
    }

    Write-Section "Pod-to-Service Networking Layer"
    Write-Explain "Curls the service name and ClusterIP from inside the cluster to separate DNS issues from service routing issues."
    if ($expectedPortMissing) {
        Add-Result -Layer "Pod-to-Service Networking Layer" -Check "service curl" -Status "SKIP" -Message "Skipped because expected port $ExpectedPort is not exposed by the service. Curl failures would be expected."
    } elseif ($debugReady -and $service -and $endpointIps.Count -eq 0) {
        Add-Result -Layer "Pod-to-Service Networking Layer" -Check "service curl" -Status "SKIP" -Message "Skipped because the service has no ready endpoints. Curl failures would be expected until pods are Ready and mapped."
    } elseif ($debugReady -and $service) {
        $urls = Get-ServiceUrls -Service $service
        foreach ($target in @(
            [PSCustomObject]@{ Name = "service short name"; Url = $urls.ShortName },
            [PSCustomObject]@{ Name = "service FQDN"; Url = $urls.Fqdn },
            [PSCustomObject]@{ Name = "ClusterIP"; Url = $urls.ClusterIp }
        )) {
            if ([string]::IsNullOrWhiteSpace($target.Url)) {
                Add-Result -Layer "Pod-to-Service Networking Layer" -Check $target.Name -Status "SKIP" -Message "Skipped $($target.Name) because no URL is available."
                continue
            }

            $curl = Invoke-InDebugPod -Command "curl -sS -o /dev/null -w 'HTTP_STATUS=%{http_code}' --connect-timeout $TimeoutSec '$($target.Url)'"
            if ($curl.ExitCode -eq 0) {
                $statusCode = Get-HttpStatusFromText -Text $curl.Text
                Add-Result -Layer "Pod-to-Service Networking Layer" -Check $target.Name -Status "PASS" -Message "$($target.Url) reachable from debug pod. HTTP status: $statusCode"
                if ($target.Name -eq "service short name") { $inClusterServiceOk = $true }
            } else {
                $serviceCurlFailures++
                Add-Result -Layer "Pod-to-Service Networking Layer" -Check $target.Name -Status "FAIL" -Message "$($target.Url) failed from debug pod. This may be DNS, TCP, NetworkPolicy, service routing, or app listener."
                if ($curl.Text) { Write-Host $curl.Text -ForegroundColor DarkGray }
            }
        }
    } elseif (-not $service) {
        Add-Result -Layer "Pod-to-Service Networking Layer" -Check "service curl" -Status "SKIP" -Message "Skipped because the service does not exist."
    }

    Write-Section "Pod-to-Pod Networking Layer"
    Write-Explain "Curls pod IPs directly from inside the cluster. If this fails while pods are Ready, suspect overlay/CNI or app bind/listen issues."
    if ($expectedPortMissing) {
        Add-Result -Layer "Pod-to-Pod Networking Layer" -Check "pod ip curl" -Status "SKIP" -Message "Skipped because expected port $ExpectedPort is not exposed by the service. Pick the service port first, then compare pod reachability."
    } elseif ($debugReady -and $podIps.Count -gt 0 -and ($selectedPodCount -gt 0 -and $readyPodCount -lt $selectedPodCount)) {
        Add-Result -Layer "Pod-to-Pod Networking Layer" -Check "pod ip curl" -Status "SKIP" -Message "Skipped because selected pods are not Ready. Direct pod curl failures would be expected."
    } elseif ($debugReady -and $podIps.Count -gt 0) {
        $urls = Get-ServiceUrls -Service $service
        foreach ($podIp in @($podIps | Sort-Object -Unique)) {
            $url = "$Scheme`://$podIp`:$($urls.Port)$(Get-UrlPath)"
            $curl = Invoke-InDebugPod -Command "curl -sS -o /dev/null -w 'HTTP_STATUS=%{http_code}' --connect-timeout $TimeoutSec '$url'"
            if ($curl.ExitCode -eq 0) {
                $podIpCurlPasses++
                $statusCode = Get-HttpStatusFromText -Text $curl.Text
                Add-Result -Layer "Pod-to-Pod Networking Layer" -Check "curl $podIp" -Status "PASS" -Message "$url reachable from debug pod. HTTP status: $statusCode"
            } else {
                Add-Result -Layer "Pod-to-Pod Networking Layer" -Check "curl $podIp" -Status "FAIL" -Message "$url failed from debug pod. Suspect CNI/overlay, NetworkPolicy, or app not listening on expected port."
                if ($selectedPodCount -gt 0 -and $readyPodCount -eq $selectedPodCount) {
                    Add-Diagnosis "Pod IP curl failed from inside the cluster while pods were Ready. Check NetworkPolicy, CNI/overlay networking, and whether the app listens on the expected port."
                }
            }
        }
    } elseif ($podIps.Count -eq 0) {
        Add-Result -Layer "Pod-to-Pod Networking Layer" -Check "pod ip curl" -Status "SKIP" -Message "Skipped because no pod IPs were found."
    }

    Write-Section "NodePort / kube-proxy Layer"
    Write-Explain "Tests NodeIP:NodePort from inside the cluster. This helps validate kube-proxy/service routing separately from Windows host routing."
    if ($SkipNodePort) {
        Add-Result -Layer "NodePort / kube-proxy Layer" -Check "nodeport" -Status "SKIP" -Message "Skipped by -SkipNodePort."
    } elseif (-not $service -or $service.spec.type -notin @("NodePort", "LoadBalancer")) {
        Add-Result -Layer "NodePort / kube-proxy Layer" -Check "nodeport" -Status "SKIP" -Message "Service type is not NodePort/LoadBalancer."
    } else {
        $nodePorts = @($service.spec.ports | Where-Object { $_.nodePort } | Select-Object -ExpandProperty nodePort)
        try {
            $nodes = ConvertFrom-KubeJson -Arguments @("get", "nodes")
            foreach ($node in @($nodes.items)) {
                $internalIp = $node.status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -First 1
                if ($internalIp.address) {
                    $nodeIps += $internalIp.address
                }
            }
        } catch {
            Add-Result -Layer "NodePort / kube-proxy Layer" -Check "node ips" -Status "WARN" -Message "Could not read node IPs: $($_.Exception.Message)"
        }

        if ($nodePorts.Count -eq 0 -or $nodeIps.Count -eq 0) {
            Add-Result -Layer "NodePort / kube-proxy Layer" -Check "nodeport data" -Status "SKIP" -Message "No nodePort or node IP values were available."
        } elseif ($debugReady) {
            foreach ($nodePort in $nodePorts) {
                foreach ($nodeIp in @($nodeIps | Sort-Object -Unique)) {
                    $url = "$Scheme`://$nodeIp`:$nodePort$(Get-UrlPath)"
                    $curl = Invoke-InDebugPod -Command "curl -sS -o /dev/null -w 'HTTP_STATUS=%{http_code}' --connect-timeout $TimeoutSec '$url'"
                    if ($curl.ExitCode -eq 0) {
                        $statusCode = Get-HttpStatusFromText -Text $curl.Text
                        Add-Result -Layer "NodePort / kube-proxy Layer" -Check "$nodeIp`:$nodePort inside cluster" -Status "PASS" -Message "$url reachable from debug pod. HTTP status: $statusCode"
                    } else {
                        Add-Result -Layer "NodePort / kube-proxy Layer" -Check "$nodeIp`:$nodePort inside cluster" -Status "FAIL" -Message "$url failed from debug pod. Suspect kube-proxy, service routing, firewall, or node networking."
                        Add-Diagnosis "NodePort failed from inside the cluster. Check kube-proxy, service NodePort allocation, node firewall, and node networking."
                    }
                }
            }
        }
    }

    Write-Section "Host-to-Cluster Layer"
    Write-Explain "Tests NodeIP:NodePort from the Windows host. In Docker Desktop/kind clusters, failures here often mean host/VM/WSL routing rather than service failure."
    if ($SkipNodePort) {
        Add-Result -Layer "Host-to-Cluster Layer" -Check "host nodeport" -Status "SKIP" -Message "Skipped by -SkipNodePort."
    } elseif (-not $service -or $service.spec.type -notin @("NodePort", "LoadBalancer")) {
        Add-Result -Layer "Host-to-Cluster Layer" -Check "host nodeport" -Status "SKIP" -Message "Service type is not NodePort/LoadBalancer."
    } elseif ($nodePorts.Count -eq 0 -or $nodeIps.Count -eq 0) {
        Add-Result -Layer "Host-to-Cluster Layer" -Check "host nodeport" -Status "SKIP" -Message "No nodePort or node IP values were available."
    } else {
        foreach ($nodePort in $nodePorts) {
            foreach ($nodeIp in @($nodeIps | Sort-Object -Unique)) {
                $url = "$Scheme`://$nodeIp`:$nodePort$(Get-UrlPath)"
                Write-Explain "Testing from Windows host: $url"
                $local = Test-LocalHttp -Url $url
                if ($local.Ok) {
                    $hostNodePortPasses++
                    Add-Result -Layer "Host-to-Cluster Layer" -Check "$nodeIp`:$nodePort from host" -Status "PASS" -Message "$url reachable from Windows host. HTTP status: $($local.StatusCode)"
                } else {
                    $hostNodePortFailures++
                    Add-Result -Layer "Host-to-Cluster Layer" -Check "$nodeIp`:$nodePort from host" -Status "FAIL" -Message "$url failed from Windows host. Likely Docker Desktop/WSL/firewall/host routing if inside-cluster checks passed."
                }
            }
        }
    }

    Write-Section "Optional Port-Forward Validation"
    Write-Explain "Port-forward can prove the service/pod works even when NodePort or host routing fails."
    if ($SkipPortForward -or -not $TestPortForward) {
        Add-Result -Layer "Optional Port-Forward Validation" -Check "port-forward" -Status "SKIP" -Message "Skipped. Add -TestPortForward to run this check."
    } elseif (-not $service) {
        Add-Result -Layer "Optional Port-Forward Validation" -Check "port-forward" -Status "SKIP" -Message "Skipped because the service does not exist."
    } else {
        $servicePort = Get-CheckPort -Service $service
        $localPort = Get-Random -Minimum 20000 -Maximum 45000
        $pfOut = [System.IO.Path]::GetTempFileName()
        $pfErr = [System.IO.Path]::GetTempFileName()
        $process = $null
        try {
            $argLine = "port-forward -n $Namespace svc/$ServiceName $localPort`:$servicePort"
            Write-Verbose "$script:Kubectl $argLine"
            $startProcessParams = @{
                FilePath               = $script:Kubectl
                ArgumentList           = $argLine
                RedirectStandardOutput = $pfOut
                RedirectStandardError  = $pfErr
                PassThru               = $true
            }
            if ($IsWindows -or $PSVersionTable.PSEdition -eq "Desktop") {
                $startProcessParams.WindowStyle = "Hidden"
            }
            $process = Start-Process @startProcessParams
            Start-Sleep -Seconds 2
            $url = "$Scheme`://127.0.0.1`:$localPort$(Get-UrlPath)"
            $pfTest = Test-LocalHttp -Url $url
            if ($pfTest.Ok) {
                Add-Result -Layer "Optional Port-Forward Validation" -Check "port-forward" -Status "PASS" -Message "Port-forward to svc/$ServiceName worked on localhost:$localPort. HTTP status: $($pfTest.StatusCode)"
            } else {
                $err = Get-Content -LiteralPath $pfErr -Raw -ErrorAction SilentlyContinue
                Add-Result -Layer "Optional Port-Forward Validation" -Check "port-forward" -Status "FAIL" -Message "Port-forward started but localhost test failed. $err"
            }
        } catch {
            Add-Result -Layer "Optional Port-Forward Validation" -Check "port-forward" -Status "FAIL" -Message "Port-forward check failed: $($_.Exception.Message)"
        } finally {
            if ($process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $pfOut, $pfErr -Force -ErrorAction SilentlyContinue
        }
    }

    if ($inClusterServiceOk -and $hostNodePortFailures -gt 0 -and $hostNodePortPasses -eq 0) {
        Add-Diagnosis "Internal service routing is healthy, but the Windows host cannot reach NodePort. Likely Docker Desktop/WSL/VM networking, firewall, or host routing."
    }

    if ($expectedPortMissing) {
        # The missing expected port is already the useful diagnosis. Avoid adding targetPort guesses.
    } elseif ($serviceCurlFailures -gt 0 -and $podIpCurlPasses -gt 0 -and $service -and $endpointIps.Count -gt 0) {
        $portMappings = @($service.spec.ports | ForEach-Object { "$($_.port)->$($_.targetPort)" }) -join ", "
        if ($targetPortAnalysis -and $targetPortAnalysis.Status -eq "Mismatch") {
            Add-Diagnosis "Primary issue: Service targetPort mismatch. Service routing fails, direct pod IP curl works, and targetPort metadata does not match selected pod container ports. Current service port mapping: $portMappings. $($targetPortAnalysis.Message)"
        } else {
            Add-Diagnosis "Primary issue: service routing fails but direct pod IP curl works. This often means the Service targetPort is wrong or does not match the port the app listens on. Current service port mapping: $portMappings."
        }
    } elseif ($targetPortAnalysis -and $targetPortAnalysis.Status -eq "Mismatch" -and $selectedPodCount -gt 0) {
        $portMappings = @($service.spec.ports | ForEach-Object { "$($_.port)->$($_.targetPort)" }) -join ", "
        Add-Diagnosis "Possible issue: Service targetPort metadata does not match selected pod container ports. This may be okay if the app listens on an undeclared port, but it is worth checking. Current service port mapping: $portMappings. $($targetPortAnalysis.Message)"
    }

    if (($script:Results | Where-Object { $_.Layer -eq "Endpoint Mapping Layer" -and $_.Status -eq "FAIL" }).Count -gt 0 -and
        ($script:Results | Where-Object { $_.Layer -eq "Pod Health Layer" -and $_.Check -eq "ready" -and $_.Status -eq "PASS" }).Count -gt 0) {
        Add-Diagnosis "Pods are Ready but endpoint mapping failed. Likely service selector mismatch or EndpointSlice/controller issue."
    }
} catch {
    if ($_.Exception.Message) {
        Write-Verbose $_.Exception.Message
    }
    $exitCode = 1
} finally {
    Remove-DebugPod
}

Write-Section "Summary"
$summary = $script:Results | Group-Object Status | Sort-Object Name
foreach ($item in $summary) {
    $color = switch ($item.Name) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        "SKIP" { "DarkYellow" }
        default { "Gray" }
    }
    Write-Host ("{0}: {1}" -f $item.Name, $item.Count) -ForegroundColor $color
}

$failures = @($script:Results | Where-Object Status -eq "FAIL")
if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Failure details:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - [$($failure.Layer)] $($failure.Check): $($failure.Message)" -ForegroundColor Red
    }
    $exitCode = 1
}

Write-Section "Diagnosis"
if ($script:Diagnoses.Count -eq 0 -and $failures.Count -eq 0) {
    Write-Host "No obvious failure domain found. The tested layers look healthy." -ForegroundColor Green
} elseif ($script:Diagnoses.Count -eq 0) {
    Write-Host "Failures were found, but no single dominant diagnosis was inferred. Review the failed layer(s) above." -ForegroundColor Yellow
} else {
    foreach ($diagnosis in $script:Diagnoses) {
        Write-Host " - $diagnosis" -ForegroundColor Yellow
    }
}

$reportTimestamp = (Get-Date).ToString("o")
$allResults = @($script:Results)
$reportDiagnoses = @($script:Diagnoses)
$reportSummary = @($allResults | Group-Object Status | Sort-Object Name | ForEach-Object {
    [PSCustomObject]@{
        Status = $_.Name
        Count  = $_.Count
    }
})
$reportFailures = @($allResults | Where-Object Status -eq "FAIL")
$reportWarnings = @($allResults | Where-Object Status -eq "WARN")
$reportResultsByLayer = @($allResults | Group-Object Layer | ForEach-Object {
    [PSCustomObject]@{
        Layer   = $_.Name
        Results = @($_.Group | Select-Object Check, Status, Message, Data)
    }
})

$report = [PSCustomObject]@{
    Target = [PSCustomObject]@{
        Namespace   = $Namespace
        Service     = $ServiceName
        Deployment  = $DeploymentName
        Timestamp   = $reportTimestamp
        KubeCommand = $script:Kubectl
        DebugImage  = $DebugImage
        Scheme      = $Scheme
        Path        = $Path
        ExpectedPort = $ExpectedPort
    }
    Diagnoses      = $reportDiagnoses
    StatusSummary  = $reportSummary
    Failures       = @($reportFailures | Select-Object Layer, Check, Status, Message, Data)
    Warnings       = @($reportWarnings | Select-Object Layer, Check, Status, Message, Data)
    ResultsByLayer = $reportResultsByLayer
    RawResults     = $allResults
}

function Escape-MarkdownCell {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return (($Text -replace "\|", "\|") -replace "`r?`n", "<br>")
}

function Encode-Html {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Convert-InlineMarkdownToHtml {
    param([string]$Text)
    $encoded = Encode-Html -Text $Text
    return ($encoded -replace '`([^`]+)`', '<code>$1</code>')
}

function Get-StatusClass {
    param([string]$Status)
    return "status status-$($Status.ToLower())"
}

if (-not [string]::IsNullOrWhiteSpace($ExportJson)) {
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ExportJson -Encoding UTF8
    Write-Host ""
    Write-Host "JSON report written to $ExportJson" -ForegroundColor Green
}

if (-not [string]::IsNullOrWhiteSpace($ExportMarkdown)) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Kubernetes Network Check")
    $lines.Add("")
    $lines.Add("## Diagnosis")
    $lines.Add("")
    if ($reportDiagnoses.Count -eq 0) {
        $lines.Add("- No dominant diagnosis inferred.")
    } else {
        foreach ($diagnosis in $reportDiagnoses) { $lines.Add("- $diagnosis") }
    }
    $lines.Add("")
    $lines.Add("## Status Summary")
    $lines.Add("")
    $lines.Add("| Status | Count |")
    $lines.Add("|---|---:|")
    foreach ($item in $reportSummary) { $lines.Add("| $($item.Status) | $($item.Count) |") }
    $lines.Add("")
    $lines.Add("## Failure Summary")
    $lines.Add("")
    $lines.Add("| Layer | Check | Message |")
    $lines.Add("|---|---|---|")
    if ($reportFailures.Count -eq 0) {
        $lines.Add("| - | - | No failures found. |")
    } else {
        foreach ($failure in $reportFailures) {
            $lines.Add("| $(Escape-MarkdownCell $failure.Layer) | $(Escape-MarkdownCell $failure.Check) | $(Escape-MarkdownCell $failure.Message) |")
        }
    }
    $lines.Add("")
    $lines.Add("## Target")
    $lines.Add("")
    $lines.Add("| Field | Value |")
    $lines.Add("|---|---|")
    $lines.Add("| Namespace | ``$Namespace`` |")
    $lines.Add("| Service | ``$ServiceName`` |")
    $lines.Add("| Deployment | ``$DeploymentName`` |")
    $lines.Add("| Timestamp | ``$reportTimestamp`` |")
    $lines.Add("| KubeCommand | ``$script:Kubectl`` |")
    $lines.Add("| DebugImage | ``$DebugImage`` |")
    $lines.Add("| Scheme | ``$Scheme`` |")
    $lines.Add("| Path | ``$Path`` |")
    $lines.Add("| ExpectedPort | ``$ExpectedPort`` |")
    $lines.Add("")
    $lines.Add("## Warnings")
    $lines.Add("")
    $lines.Add("| Layer | Check | Message |")
    $lines.Add("|---|---|---|")
    if ($reportWarnings.Count -eq 0) {
        $lines.Add("| - | - | No warnings found. |")
    } else {
        foreach ($warning in $reportWarnings) {
            $lines.Add("| $(Escape-MarkdownCell $warning.Layer) | $(Escape-MarkdownCell $warning.Check) | $(Escape-MarkdownCell $warning.Message) |")
        }
    }
    $lines.Add("")
    $lines.Add("## Results By Layer")
    foreach ($group in ($allResults | Group-Object Layer)) {
        $lines.Add("")
        $lines.Add("### $($group.Name)")
        $lines.Add("")
        $lines.Add("| Check | Status | Message |")
        $lines.Add("|---|---|---|")
        foreach ($row in $group.Group) {
            $lines.Add("| $(Escape-MarkdownCell $row.Check) | $($row.Status) | $(Escape-MarkdownCell $row.Message) |")
        }
    }
    $lines | Set-Content -LiteralPath $ExportMarkdown -Encoding UTF8
    Write-Host "Markdown report written to $ExportMarkdown" -ForegroundColor Green
}

if (-not [string]::IsNullOrWhiteSpace($ExportHtml)) {
    $targetRows = foreach ($property in $report.Target.PSObject.Properties) {
        "<tr><th>$(Encode-Html $property.Name)</th><td><code>$(Encode-Html ([string]$property.Value))</code></td></tr>"
    }

    $diagnosisItems = if ($reportDiagnoses.Count -gt 0) {
        foreach ($diagnosis in $reportDiagnoses) { "<li>$(Convert-InlineMarkdownToHtml $diagnosis)</li>" }
    } else {
        "<li>No dominant diagnosis inferred.</li>"
    }

    $summaryCards = foreach ($item in $reportSummary) {
        $className = $item.Status.ToLower()
        "<div class='stat stat-$className'><span>$(Encode-Html $item.Status)</span><strong>$($item.Count)</strong></div>"
    }

    $failureRows = if ($reportFailures.Count -gt 0) {
        foreach ($result in $reportFailures) {
            "<tr><td>$(Encode-Html $result.Layer)</td><td>$(Encode-Html $result.Check)</td><td><span class='$(Get-StatusClass $result.Status)'>$(Encode-Html $result.Status)</span></td><td>$(Convert-InlineMarkdownToHtml $result.Message)</td></tr>"
        }
    } else {
        "<tr><td colspan='4'>No failures found.</td></tr>"
    }

    $warningRows = if ($reportWarnings.Count -gt 0) {
        foreach ($result in $reportWarnings) {
            "<tr><td>$(Encode-Html $result.Layer)</td><td>$(Encode-Html $result.Check)</td><td><span class='$(Get-StatusClass $result.Status)'>$(Encode-Html $result.Status)</span></td><td>$(Convert-InlineMarkdownToHtml $result.Message)</td></tr>"
        }
    } else {
        "<tr><td colspan='4'>No warnings found.</td></tr>"
    }

    $layerSections = foreach ($group in ($allResults | Group-Object Layer)) {
        $rows = foreach ($result in $group.Group) {
            "<tr><td>$(Encode-Html $result.Check)</td><td><span class='$(Get-StatusClass $result.Status)'>$(Encode-Html $result.Status)</span></td><td>$(Convert-InlineMarkdownToHtml $result.Message)</td></tr>"
        }
@"
<section class='panel'>
  <h3>$(Encode-Html $group.Name)</h3>
  <table>
    <thead><tr><th>Check</th><th>Status</th><th>Message</th></tr></thead>
    <tbody>$($rows -join "`n")</tbody>
  </table>
</section>
"@
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kubernetes Network Check</title>
<style>
:root {
  --bg: #0d1117;
  --panel: #161b22;
  --panel-2: #0f1722;
  --text: #e6edf3;
  --muted: #8b949e;
  --border: #30363d;
  --pass: #3fb950;
  --fail: #ff6b6b;
  --warn: #d29922;
  --skip: #a371f7;
  --info: #58a6ff;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: "Segoe UI", Arial, sans-serif;
  line-height: 1.5;
}
main { max-width: 1220px; margin: 0 auto; padding: 32px 24px 56px; }
h1 { margin: 0 0 18px; font-size: 34px; letter-spacing: 0; }
h2 { margin: 0 0 14px; font-size: 22px; }
h3 { margin: 0 0 12px; font-size: 18px; color: var(--text); }
.grid { display: grid; grid-template-columns: 1.4fr .9fr; gap: 16px; align-items: start; }
.panel {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 18px;
  margin: 16px 0;
}
.diagnosis { border-left: 4px solid var(--fail); }
.diagnosis ul { margin: 0; padding-left: 20px; }
.diagnosis li { margin: 8px 0; font-size: 16px; }
.meta-table th {
  width: 132px;
  color: var(--muted);
  font-weight: 600;
}
.meta-table th, .meta-table td {
  border-bottom: 1px solid var(--border);
}
code {
  background: rgba(110,118,129,.25);
  color: var(--text);
  border-radius: 4px;
  padding: 2px 5px;
  font-family: Consolas, "Courier New", monospace;
  overflow-wrap: anywhere;
}
.stats { display: grid; grid-template-columns: repeat(5, minmax(90px, 1fr)); gap: 10px; }
.stat {
  background: var(--panel-2);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px;
}
.stat span { display: block; color: var(--muted); font-size: 12px; font-weight: 700; }
.stat strong { display: block; font-size: 26px; margin-top: 2px; }
.stat-pass strong { color: var(--pass); }
.stat-fail strong { color: var(--fail); }
.stat-warn strong { color: var(--warn); }
.stat-skip strong { color: var(--skip); }
.stat-info strong { color: var(--info); }
table { width: 100%; border-collapse: collapse; }
th, td {
  border-bottom: 1px solid var(--border);
  padding: 10px 12px;
  text-align: left;
  vertical-align: top;
  font-size: 14px;
}
th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
tr:last-child td { border-bottom: 0; }
.status { font-weight: 800; white-space: nowrap; }
.status-pass { color: var(--pass); }
.status-fail { color: var(--fail); }
.status-warn { color: var(--warn); }
.status-skip { color: var(--skip); }
.status-info { color: var(--info); }
@media (max-width: 880px) {
  main { padding: 22px 12px 40px; }
  .grid { grid-template-columns: 1fr; }
  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  table { display: block; overflow-x: auto; }
}
</style>
</head>
<body>
<main>
  <h1>Kubernetes Network Check</h1>

  <section class='grid'>
    <div class='panel diagnosis'>
      <h2>Diagnosis</h2>
      <ul>$($diagnosisItems -join "`n")</ul>
    </div>
    <div class='panel'>
      <h2>Target</h2>
      <table class='meta-table'><tbody>$($targetRows -join "`n")</tbody></table>
    </div>
  </section>

  <section class='panel'>
    <h2>Status Summary</h2>
    <div class='stats'>$($summaryCards -join "`n")</div>
  </section>

  <section class='panel'>
    <h2>Failures</h2>
    <table><thead><tr><th>Layer</th><th>Check</th><th>Status</th><th>Message</th></tr></thead><tbody>$($failureRows -join "`n")</tbody></table>
  </section>

  <section class='panel'>
    <h2>Warnings</h2>
    <table><thead><tr><th>Layer</th><th>Check</th><th>Status</th><th>Message</th></tr></thead><tbody>$($warningRows -join "`n")</tbody></table>
  </section>

  <h2 style='margin-top:28px'>Results By Layer</h2>
  $($layerSections -join "`n")
</main>
</body>
</html>
"@

    $html | Set-Content -LiteralPath $ExportHtml -Encoding UTF8
    Write-Host "HTML report written to $ExportHtml" -ForegroundColor Green
}

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
}

exit $exitCode
