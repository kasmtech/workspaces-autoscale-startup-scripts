#ps1_sysnative

param(
    [Parameter(Mandatory=$false)]
    [bool]$SkipDisableNetBios=$false,

    [Parameter(Mandatory=$false)]
    [bool]$ComputerRename=$false,

    [Parameter(Mandatory=$false)]
    [bool]$DomainJoin=$false
)

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

Function Get-IsInstantClone {
    try {
        $CloneType = & vmware-rpctool "info-get guestinfo.clone.type" 2>$null
        return ($CloneType -and $CloneType.Trim() -eq "instant")
    } catch {
        return $false
    }
}

Function Disable-NetBios {
    Write-Log "Checking NetBIOS status on network interfaces"

    $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"

    foreach ($interface in $interfaces) {
        $current = (Get-ItemProperty -Path $interface.PSPath).NetbiosOptions
        if ($current -ne 2) {
            Set-ItemProperty -Path $interface.PSPath -Name NetbiosOptions -Value 2
            Write-Log "NetBIOS disabled on $($interface.PSChildName)"
        } else {
            Write-Log "NetBIOS already disabled on $($interface.PSChildName)"
        }
    }
}

Function Reset-MachineGuid {
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
    $currentGuid = (Get-ItemProperty -Path $registryPath).MachineGuid
    $newGuid = [System.Guid]::NewGuid().ToString()

    Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid
    Write-Log "Machine GUID regenerated from $currentGuid to $newGuid"
}

Function Clear-DnsCache {
    Write-Log "Flushing DNS cache"
    Clear-DnsClientCache
    Write-Log "DNS cache flushed"
}

### Main script execution ###

if (-not (Get-IsInstantClone)) {
    Write-Log "Not an instant clone. Skipping instant clone initialization."
    return
}

Reset-MachineGuid

if ($ComputerRename -or $DomainJoin) {
    Write-Log "Reboot pending. Skipping NetBIOS and DNS cache configuration."
} else {
    if (-not $SkipDisableNetBios) {
        Disable-NetBios
    }

    Clear-DnsCache
}