param(
    [string]$SourceDirectory,
    [string]$OutputPath,
    [string]$Title = 'ATO-MATIC Master Checklist'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $SourceDirectory) {
    $SourceDirectory = Join-Path $projectRoot '.tmp\stig-xccdf'
}
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot 'MASTER-CHECKLIST.cklb'
}

if (-not (Test-Path $SourceDirectory)) {
    throw "XCCDF source directory was not found: $SourceDirectory"
}

function Get-Text {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$XPath
    )

    $selectedNode = $Node.SelectSingleNode($XPath)
    if ($selectedNode) {
        return $selectedNode.InnerText.Trim()
    }
    return ''
}

function Get-DescriptionFields {
    param([string]$Description)

    $fields = @{
        VulnDiscussion = ''
        FalsePositives = ''
        FalseNegatives = ''
        Documentable = 'false'
        Mitigations = ''
        SeverityOverrideGuidance = ''
        PotentialImpacts = ''
        ThirdPartyTools = ''
        MitigationControl = ''
        Responsibility = ''
        IAControls = ''
    }

    if (-not $Description) {
        return $fields
    }

    try {
        [xml]$descriptionXml = "<root>$Description</root>"
        foreach ($key in @($fields.Keys)) {
            $node = $descriptionXml.SelectSingleNode("//$key")
            if ($node) {
                $fields[$key] = $node.InnerText.Trim()
            }
        }
    } catch {
        $fields.VulnDiscussion = $Description.Trim()
    }

    return $fields
}

function New-RuleObject {
    param(
        [System.Xml.XmlNode]$Group,
        [System.Xml.XmlNode]$Rule,
        [string]$StigUuid
    )

    $ruleIdSource = $Rule.id
    $ruleId = $ruleIdSource -replace '_rule$', ''
    $groupId = $Group.id
    $groupTitle = Get-Text -Node $Group -XPath "*[local-name()='title']"
    $groupDescription = Get-Text -Node $Group -XPath "*[local-name()='description']"
    $descriptionFields = Get-DescriptionFields -Description (Get-Text -Node $Rule -XPath "*[local-name()='description']")
    $legacyIds = @()
    $ccis = @()

    foreach ($ident in $Rule.SelectNodes("*[local-name()='ident']")) {
        if ($ident.system -eq 'http://cyber.mil/legacy') {
            $legacyIds += $ident.InnerText.Trim()
        } elseif ($ident.system -eq 'http://cyber.mil/cci') {
            $ccis += $ident.InnerText.Trim()
        }
    }

    $checkContentRef = $Rule.SelectSingleNode("*[local-name()='check']/*[local-name()='check-content-ref']")
    $checkRef = @{
        href = ''
        name = ''
    }
    if ($checkContentRef) {
        $checkRef.href = $checkContentRef.href
        $checkRef.name = $checkContentRef.name
    }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [ordered]@{
        uuid = [guid]::NewGuid().ToString()
        stig_uuid = $StigUuid
        target_key = $null
        stig_ref = $null
        group_id = $groupId
        rule_id = $ruleId
        rule_id_src = $ruleIdSource
        weight = if ($Rule.weight) { [string]$Rule.weight } else { '10.0' }
        classification = 'Unclassified'
        severity = if ($Rule.severity) { [string]$Rule.severity } else { 'unknown' }
        rule_version = Get-Text -Node $Rule -XPath "*[local-name()='version']"
        group_title = if ($groupTitle) { $groupTitle } else { Get-Text -Node $Rule -XPath "*[local-name()='title']" }
        rule_title = Get-Text -Node $Rule -XPath "*[local-name()='title']"
        fix_text = Get-Text -Node $Rule -XPath "*[local-name()='fixtext']"
        false_positives = $descriptionFields.FalsePositives
        false_negatives = $descriptionFields.FalseNegatives
        discussion = $descriptionFields.VulnDiscussion
        check_content = Get-Text -Node $Rule -XPath "*[local-name()='check']/*[local-name()='check-content']"
        documentable = if ($descriptionFields.Documentable) { $descriptionFields.Documentable } else { 'false' }
        mitigations = $descriptionFields.Mitigations
        potential_impacts = $descriptionFields.PotentialImpacts
        third_party_tools = $descriptionFields.ThirdPartyTools
        mitigation_control = $descriptionFields.MitigationControl
        responsibility = $descriptionFields.Responsibility
        security_override_guidance = $descriptionFields.SeverityOverrideGuidance
        ia_controls = $descriptionFields.IAControls
        check_content_ref = $checkRef
        legacy_ids = @($legacyIds)
        ccis = @($ccis)
        group_tree = @(
            [ordered]@{
                id = $groupId
                title = $groupTitle
                description = $groupDescription
            }
        )
        createdAt = $now
        updatedAt = $now
        STIGUuid = $StigUuid
        status = 'not_reviewed'
        overrides = [ordered]@{}
        comments = ''
        finding_details = ''
    }
}

$stigs = New-Object System.Collections.Generic.List[object]
$xmlFiles = Get-ChildItem -Path $SourceDirectory -Filter '*.xml' -File | Sort-Object Name

foreach ($file in $xmlFiles) {
    [xml]$xml = Get-Content -Path $file.FullName -Raw
    $benchmark = $xml.SelectSingleNode("/*[local-name()='Benchmark']")
    if (-not $benchmark) {
        continue
    }

    $stigUuid = [guid]::NewGuid().ToString()
    $rules = New-Object System.Collections.Generic.List[object]

    foreach ($group in $benchmark.SelectNodes("*[local-name()='Group']")) {
        foreach ($rule in $group.SelectNodes("*[local-name()='Rule']")) {
            $rules.Add((New-RuleObject -Group $group -Rule $rule -StigUuid $stigUuid))
        }
    }

    if ($rules.Count -eq 0) {
        continue
    }

    $displayName = Get-Text -Node $benchmark -XPath ".//*[local-name()='reference']/*[local-name()='subject']"
    if (-not $displayName) {
        $displayName = Get-Text -Node $benchmark -XPath "*[local-name()='title']"
    }

    $stigName = Get-Text -Node $benchmark -XPath "*[local-name()='title']"
    $benchmarkId = $benchmark.GetAttribute('id')
    $releaseInfo = Get-Text -Node $benchmark -XPath "*[local-name()='plain-text'][@id='release-info']"
    $referenceIdentifier = Get-Text -Node $benchmark -XPath ".//*[local-name()='reference']/*[local-name()='identifier']"
    $stigs.Add([ordered]@{
        stig_name = $stigName
        display_name = $displayName
        stig_id = $benchmarkId
        release_info = $releaseInfo
        uuid = $stigUuid
        reference_identifier = $referenceIdentifier
        size = $rules.Count
        rules = $rules.ToArray()
    })
}

if ($stigs.Count -eq 0) {
    throw "No STIGs were generated from $SourceDirectory"
}

$checklist = [ordered]@{
    title = $Title
    id = [guid]::NewGuid().ToString()
    stigs = $stigs.ToArray()
    active = $true
    mode = 2
    has_path = $false
    target_data = [ordered]@{
        target_type = 'Computing'
        host_name = ''
        ip_address = ''
        mac_address = ''
        fqdn = ''
        comments = ''
        role = ''
        is_web_database = $false
        technology_area = ''
        web_db_site = ''
        web_db_instance = ''
        classification = 'Unclassified'
    }
    cklb_version = '1.0'
}

$outputDirectory = Split-Path $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$json = $checklist | ConvertTo-Json -Depth 100 -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -Path $OutputPath), $json, $utf8NoBom)

$ruleCount = ($stigs | ForEach-Object { $_.size } | Measure-Object -Sum).Sum
Write-Host "Wrote master checklist with $($stigs.Count) STIGs and $ruleCount rules to $OutputPath"
