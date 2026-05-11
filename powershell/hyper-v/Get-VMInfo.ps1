Function Get-VMInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
        [string[]]$Name
    )
    if ($Name -ne $null -and $Name -ne '') {
        $vms = Get-VM -Name $Name
    } else {
        $vms = Get-VM
    }
    $result = foreach ($vm in $vms) {
        $vm | Select-Object Name,
        @{n='RAM';e={echo "$($_.MemoryAssigned/1gb)GB"}},
        @{n='Cores';e={($_ | Get-VMProcessor).count}},
        @{n='HD Size';e={($_.Vmid | Get-VHD) | foreach{echo "$($_.size/1gb)GB"}}}
    }
    $result
}
