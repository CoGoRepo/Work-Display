# Function to check registry key value
function CheckRegistryKey {
    param(
        [string]$RuleID,
        [string]$KeyName,
        [string]$Path,
        [string]$Tvalue,
        [string]$Operator,
        [string]$Evalue
    )

    # Get actual registry key value
    $ActualValue = Get-ItemPropertyValue -Path $Path -Name $KeyName -ErrorAction SilentlyContinue

    # Perform comparison based on operator
    switch ($Operator) {
        "eq" {
            if (($ActualValue -eq $Evalue) -or ($ActualValue -contains $Evalue)) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "ne" {
            if ($ActualValue -ne $Evalue) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "gt" {
            if ($ActualValue -gt $Evalue) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "lt" {
            if ($ActualValue -lt $Evalue) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "ge" {
            if ($ActualValue -ge $Evalue) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "le" {
            if ($ActualValue -le $Evalue) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        "lenz" {
            if (($ActualValue -le $Evalue) -and ($ActualValue -ne 0)) {
                $Result = "not_a_finding"
            } else {
                $Result = "open"
            }
        }
        default {
            Write-Host "Invalid operator: $Operator" -ForegroundColor Red
            $Result = "Invalid Operator"
        }
    }

    # Output the result
    [PSCustomObject]@{
        "Rule-ID" = $RuleID
        "Key-Name" = $KeyName
        "Path" = $Path
        "Tvalue" = $ActualValue
        "Operator" = $Operator
        "Evalue" = $Evalue
        "Results" = $Result
    }
}


# Read the CSV file
$data = Import-Csv -Path "C:\util\COGO\testing\Reg-checks.csv"

# Create an array to store the results
$results = @()

# Loop through each row in the CSV file
foreach ($row in $data) {
    # Call the CheckRegistryKey function with the provided parameters
    $result = CheckRegistryKey -RuleID $row.'Rule-ID' -KeyName $row.'Key-Name' -Path $row.Path -Tvalue $row.Tvalue -Operator $row.Operator -Evalue $row.Evalue
    
    # Add the result to the array
    $results += $result
}

# Export the results to a new CSV file
$results | Export-Csv -Path "C:\util\COGO\testing\Results.csv" -NoTypeInformation
