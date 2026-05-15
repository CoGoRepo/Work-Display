function Test-KubeNetCalicoSimpleSelector {
    param([string]$Selector, [object]$Pod, [object]$Namespace)

    if ([string]::IsNullOrWhiteSpace($Selector) -or $Selector -eq 'all()') { return $true }
    $clauses = @($Selector -split '\s+&&\s+')
    foreach ($clause in $clauses) {
        $clean = $clause.Trim()
        if ($clean -eq 'all()') { continue }
        if ($clean -match '^([A-Za-z0-9_./-]+)\s*==\s*["'']?([^"'']+)["'']?$') {
            $key = $Matches[1]
            $expected = $Matches[2]
            $actual = if ($key -in @('projectcalico.org/name', 'kubernetes.io/metadata.name')) { [string]$Namespace.metadata.name } else { [string]$Pod.metadata.labels.$key }
            if ($actual -ne $expected) { return $false }
        } else {
            return $false
        }
    }
    $true
}

function Test-KubeNetCalicoNamespaceSelector {
    param([string]$Selector, [object]$Namespace)

    if ([string]::IsNullOrWhiteSpace($Selector) -or $Selector -eq 'all()') { return $true }
    $clauses = @($Selector -split '\s+&&\s+')
    foreach ($clause in $clauses) {
        $clean = $clause.Trim()
        if ($clean -eq 'all()') { continue }
        if ($clean -match '^([A-Za-z0-9_./-]+)\s*==\s*["'']?([^"'']+)["'']?$') {
            $key = $Matches[1]
            $expected = $Matches[2]
            $actual = if ($key -in @('projectcalico.org/name', 'kubernetes.io/metadata.name')) {
                [string]$Namespace.metadata.name
            } else {
                [string]$Namespace.metadata.labels.$key
            }
            if ($actual -ne $expected) { return $false }
        } else {
            return $false
        }
    }
    $true
}

function Test-KubeNetCalicoPolicyAppliesToPod {
    param([object]$Policy, [object]$Pod, [object]$Namespace)

    $policyNamespace = [string]$Policy.metadata.namespace
    $isGlobal = [string]$Policy.kind -eq 'GlobalNetworkPolicy' -or [string]::IsNullOrWhiteSpace($policyNamespace)
    if (-not $isGlobal -and [string]$Pod.metadata.namespace -ne $policyNamespace) {
        return $false
    }

    Test-KubeNetCalicoSimpleSelector -Selector ([string]$Policy.spec.selector) -Pod $Pod -Namespace $Namespace
}

function Test-KubeNetCalicoPortMatch {
    param([object[]]$RulePorts, [int[]]$Ports)

    if ($null -eq $RulePorts -or @($RulePorts).Count -eq 0) { return $true }
    $portsToCheck = @($Ports | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    foreach ($rulePort in @($RulePorts)) {
        $number = 0
        if ([int]::TryParse([string]$rulePort, [ref]$number) -and ($portsToCheck -contains $number)) { return $true }
    }
    $false
}

function Test-KubeNetCalicoRuleLooksLikeDnsAllow {
    param([object]$Rule)

    if ($null -eq $Rule -or [string]$Rule.action -ne 'Allow') { return $false }
    if (-not (Test-KubeNetCalicoPortMatch -RulePorts @($Rule.destination.ports) -Ports @(53))) { return $false }

    $namespaceSelector = [string]$Rule.destination.namespaceSelector
    $selector = [string]$Rule.destination.selector
    if ([string]::IsNullOrWhiteSpace($namespaceSelector) -and [string]::IsNullOrWhiteSpace($selector)) {
        return $true
    }

    if ($namespaceSelector -match 'kube-system|all\(\)') {
        return $true
    }

    if ($selector -match 'kube-dns|coredns|node-local-dns|nodelocaldns') {
        return $true
    }

    $false
}

function Test-KubeNetCalicoPolicyPath {
    param(
        [object[]]$Policies,
        [object]$SourcePod,
        [object]$SourceNamespace,
        [object[]]$TargetPods,
        [object]$TargetNamespace,
        [object]$Service,
        [int[]]$Ports
    )

    if ($Policies.Count -eq 0) {
        return [PSCustomObject]@{ Results = @([PSCustomObject]@{ Check = 'Calico deny policies'; Status = 'INFO'; Message = 'No Calico NetworkPolicy/GlobalNetworkPolicy objects were found or readable.' }); Diagnoses = @() }
    }

    $matchingRules = @()
    $sourceEgressEnforcing = @()
    $sourceDnsAllow = @()
    $targetIngressEnforcing = @()
    foreach ($policy in @($Policies | Where-Object { $null -ne $_ })) {
        $policyNamespace = [string]$policy.metadata.namespace
        $policyName = if ([string]::IsNullOrWhiteSpace($policyNamespace)) { $policy.metadata.name } else { "$policyNamespace/$($policy.metadata.name)" }
        $policyOrder = 1000000.0
        $parsedOrder = 0.0
        if ([double]::TryParse([string]$policy.spec.order, [ref]$parsedOrder)) {
            $policyOrder = $parsedOrder
        }

        $ruleIndex = 0
        foreach ($rule in @($policy.spec.egress | Where-Object { $null -ne $_ })) {
            $ruleIndex++
            $action = [string]$rule.action
            if ($action -notin @('Allow', 'Deny')) { continue }
            if (-not (Test-KubeNetCalicoPolicyAppliesToPod -Policy $policy -Pod $SourcePod -Namespace $SourceNamespace)) { continue }
            $sourceEgressEnforcing += $policyName
            if (Test-KubeNetCalicoRuleLooksLikeDnsAllow -Rule $rule) {
                $sourceDnsAllow += "$policyName egress"
            }
            if (-not (Test-KubeNetCalicoNamespaceSelector -Selector ([string]$rule.destination.namespaceSelector) -Namespace $TargetNamespace)) { continue }
            if (-not (Test-KubeNetCalicoPortMatch -RulePorts @($rule.destination.ports) -Ports $Ports)) { continue }
            $destinationSelector = [string]$rule.destination.selector
            if ([string]::IsNullOrWhiteSpace($destinationSelector)) {
                $matchingRules += [PSCustomObject]@{ Policy = $policyName; Direction = 'egress'; Action = $action; Order = $policyOrder; RuleIndex = $ruleIndex }
                continue
            }
            $targetMatches = @($TargetPods | Where-Object { Test-KubeNetCalicoSimpleSelector -Selector $destinationSelector -Pod $_ -Namespace $TargetNamespace })
            if ($targetMatches.Count -gt 0) {
                $matchingRules += [PSCustomObject]@{ Policy = $policyName; Direction = 'egress'; Action = $action; Order = $policyOrder; RuleIndex = $ruleIndex }
            }
        }

        $ruleIndex = 0
        foreach ($rule in @($policy.spec.ingress | Where-Object { $null -ne $_ })) {
            $ruleIndex++
            $action = [string]$rule.action
            if ($action -notin @('Allow', 'Deny')) { continue }
            foreach ($targetPod in @($TargetPods)) {
                if (Test-KubeNetCalicoPolicyAppliesToPod -Policy $policy -Pod $targetPod -Namespace $TargetNamespace) {
                    $targetIngressEnforcing += $policyName
                }
            }
            if (-not (Test-KubeNetCalicoNamespaceSelector -Selector ([string]$rule.source.namespaceSelector) -Namespace $SourceNamespace)) { continue }
            if (-not (Test-KubeNetCalicoPortMatch -RulePorts @($rule.destination.ports) -Ports $Ports)) { continue }
            foreach ($targetPod in @($TargetPods)) {
                if (-not (Test-KubeNetCalicoPolicyAppliesToPod -Policy $policy -Pod $targetPod -Namespace $TargetNamespace)) { continue }
                $sourceSelector = [string]$rule.source.selector
                if ([string]::IsNullOrWhiteSpace($sourceSelector) -or (Test-KubeNetCalicoSimpleSelector -Selector $sourceSelector -Pod $SourcePod -Namespace $SourceNamespace)) {
                    $matchingRules += [PSCustomObject]@{ Policy = $policyName; Direction = 'ingress'; Action = $action; Order = $policyOrder; RuleIndex = $ruleIndex }
                }
            }
        }
    }

    $orderedMatches = @($matchingRules | Sort-Object Order, RuleIndex, Policy, Direction)
    $firstMatch = $orderedMatches | Select-Object -First 1
    if ($firstMatch -and $firstMatch.Action -eq 'Deny') {
        $unique = @($orderedMatches | Where-Object { $_.Action -eq 'Deny' } | ForEach-Object { "$($_.Policy) $($_.Direction) Deny" } | Sort-Object -Unique)
        return [PSCustomObject]@{
            Results = @([PSCustomObject]@{ Check = 'Calico explicit deny'; Status = 'FAIL'; Message = "Calico explicit Deny rule(s) appear to match this source-to-target path: $($unique -join ', ')." })
            Diagnoses = @("Primary issue: Calico explicit Deny policy appears to block '$($SourcePod.metadata.namespace)/$($SourcePod.metadata.name)' to service '$($TargetNamespace.metadata.name)/$($Service.metadata.name)'. Matching deny rule(s): $($unique -join ', ').")
        }
    }

    if ($firstMatch -and $firstMatch.Action -eq 'Allow' -and @($orderedMatches | Where-Object { $_.Action -eq 'Deny' }).Count -gt 0) {
        if ($sourceEgressEnforcing.Count -gt 0 -and $sourceDnsAllow.Count -eq 0) {
            $policyNames = @($sourceEgressEnforcing | Sort-Object -Unique)
            return [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{ Check = 'Calico explicit deny'; Status = 'PASS'; Message = "A Calico Allow rule appears to match this path before later Deny rule(s). First match: $($firstMatch.Policy) $($firstMatch.Direction) Allow." },
                    [PSCustomObject]@{ Check = 'Calico DNS egress allow'; Status = 'WARN'; Message = "Calico policy selects source pod '$($SourcePod.metadata.name)' for egress, and no obvious DNS egress allow rule was found. DNS lookups may fail even if the target service is allowed. Selecting policy/policies: $($policyNames -join ', ')." }
                )
                Diagnoses = @("Likely issue: Calico egress default-deny may block DNS from '$($SourcePod.metadata.namespace)/$($SourcePod.metadata.name)'. Add UDP/TCP 53 egress to CoreDNS/NodeLocalDNS or add an appropriate DNS allow policy. Policies: $($policyNames -join ', ').")
            }
        }

        return [PSCustomObject]@{
            Results = @([PSCustomObject]@{ Check = 'Calico explicit deny'; Status = 'PASS'; Message = "A Calico Allow rule appears to match this path before later Deny rule(s). First match: $($firstMatch.Policy) $($firstMatch.Direction) Allow." })
            Diagnoses = @()
        }
    }

    if ($firstMatch -and $firstMatch.Action -eq 'Allow' -and $sourceEgressEnforcing.Count -gt 0 -and $sourceDnsAllow.Count -eq 0) {
        $policyNames = @($sourceEgressEnforcing | Sort-Object -Unique)
        return [PSCustomObject]@{
            Results = @(
                [PSCustomObject]@{ Check = 'Calico explicit deny'; Status = 'PASS'; Message = "A Calico Allow rule appears to match this path. First match: $($firstMatch.Policy) $($firstMatch.Direction) Allow." },
                [PSCustomObject]@{ Check = 'Calico DNS egress allow'; Status = 'WARN'; Message = "Calico policy selects source pod '$($SourcePod.metadata.name)' for egress, and no obvious DNS egress allow rule was found. DNS lookups may fail even if the target service is allowed. Selecting policy/policies: $($policyNames -join ', ')." }
            )
            Diagnoses = @("Likely issue: Calico egress default-deny may block DNS from '$($SourcePod.metadata.namespace)/$($SourcePod.metadata.name)'. Add UDP/TCP 53 egress to CoreDNS/NodeLocalDNS or add an appropriate DNS allow policy. Policies: $($policyNames -join ', ').")
        }
    }

    if ($orderedMatches.Count -eq 0 -and $sourceEgressEnforcing.Count -gt 0) {
        $policyNames = @($sourceEgressEnforcing | Sort-Object -Unique)
        return [PSCustomObject]@{
            Results = @([PSCustomObject]@{ Check = 'Calico egress default-deny'; Status = 'FAIL'; Message = "Calico policy selects source pod '$($SourcePod.metadata.name)' for egress, but no Calico egress Allow rule obviously matches this target/port. Selecting policy/policies: $($policyNames -join ', ')." })
            Diagnoses = @("Primary issue: Calico policy selects source pod '$($SourcePod.metadata.namespace)/$($SourcePod.metadata.name)' for egress default-deny, but no egress Allow rule obviously permits service '$($TargetNamespace.metadata.name)/$($Service.metadata.name)'. Policies: $($policyNames -join ', ').")
        }
    }

    if ($orderedMatches.Count -eq 0 -and $targetIngressEnforcing.Count -gt 0) {
        $policyNames = @($targetIngressEnforcing | Sort-Object -Unique)
        return [PSCustomObject]@{
            Results = @([PSCustomObject]@{ Check = 'Calico ingress default-deny'; Status = 'FAIL'; Message = "Calico policy selects target pod(s) for ingress, but no Calico ingress Allow rule obviously matches this source/port. Selecting policy/policies: $($policyNames -join ', ')." })
            Diagnoses = @("Primary issue: Calico policy selects target service pods in '$($TargetNamespace.metadata.name)' for ingress default-deny, but no ingress Allow rule obviously permits source pod '$($SourcePod.metadata.namespace)/$($SourcePod.metadata.name)'. Policies: $($policyNames -join ', ').")
        }
    }

    [PSCustomObject]@{
        Results = @([PSCustomObject]@{ Check = 'Calico explicit deny'; Status = 'PASS'; Message = 'No Calico Deny rule obviously matches this path. Complex selectors are treated conservatively.' })
        Diagnoses = @()
    }
}
