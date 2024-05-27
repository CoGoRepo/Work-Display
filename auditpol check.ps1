# Check if the server is a domain controller
if ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -eq 2) {
    $ServerRole = "DC"
} else {
    $ServerRole = "member"
}

# Import audit rules from CSV
$auditRules = Import-Csv -Path "C:\util\Auditpol.csv"

# Function to check if a rule's configuration matches its FixText
function CheckRuleConfiguration {
    param (
        [string]$Subcat,
        [string]$Value,
        [string]$Role
    )

    $auditPolicy = auditpol /get /subcategory:"$Subcat"
    $settingValue = $auditPolicy | Select-String -Pattern ".*$Value.*"

    if ($settingValue) {
        return "not_a_finding"
    } else {
        return "open"
    }
}

# Loop through each rule and check its configuration
foreach ($auditRule in $auditRules) {
    $subcat = $auditRule.Subcat
    $value = $auditRule.Value
    $role = $auditRule.Role
    $results = CheckRuleConfiguration -Subcat $subcat -Value $value -Role $role

    # Override results to "NA" if the rule is for a domain controller and the server is not a domain controller
    if ($role -eq "DC" -and $ServerRole -ne "DC") {
        $results = "not_applicable"
    }

    # Update the Results column
    $auditRule.Results = $results
}
