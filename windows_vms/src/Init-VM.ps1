#ps1_sysnative

param(
    [Parameter(Mandatory=$false)]
    [string]$DomainName,

    [Parameter(Mandatory=$false)]
    [string]$ActiveDirectoryCredential,
    
    [Parameter(Mandatory=$false)]
    [string[]]$DnsServers,

    [Parameter(Mandatory=$false)]
    [string]$KasmHostname,

    [Parameter(Mandatory=$false)]
    [string]$RegistrationToken,

    [Parameter(Mandatory=$false)]
    [string]$ServerId,

    [Parameter(Mandatory=$false)]
    [string]$ServerName,

    [Parameter(Mandatory=$false)]
    [string]$FSLogix_ProfileLocations,

    [Parameter(Mandatory=$false)]
    [string]$FSLogix_CloudCache,

    [Parameter(Mandatory=$false)]
    [string]$FSLogix_ProfileType,

    [Parameter(Mandatory=$false)]
    [switch]$SkipStartAudioService,

    [Parameter(Mandatory=$false)]
    [switch]$RenameComputer,

    [Parameter(Mandatory=$false)]
    [switch]$KeepTaskActionScripts
)

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)

# Catch terminating errors before Import-Module runs, when Write-Log is not yet available
trap {
    "$(Get-Date -Format o)`tFATAL: $_" | Out-File -FilePath "$ScriptDirectory\kasm_startup_script.log" -Append -Encoding utf8
    exit 1
}

Import-Module $ScriptDirectory\Utils.psm1 -Force
Set-LoggingProperties -KasmHostname $KasmHostname -Token $RegistrationToken -ServerName $ServerName

$DesktopServiceScript = "$ScriptDirectory\Install-KasmDesktopService.ps1"
$DomainJoinScript = "$ScriptDirectory\Join-Domain.ps1"
$FSLogixScript = "$ScriptDirectory\Install-FSLogix.ps1"
$AudioServiceScript = "$ScriptDirectory\Start-AudioService.ps1"
$InstantCloneScript = "$ScriptDirectory\Initialize-InstantClone.ps1"

Function Invoke-DesktopServiceScript {
    if (-not $KasmHostname) {
        Write-Log "No value set for KasmHostname. Skipping Kasm Desktop Service installation."
    } elseif (-not $RegistrationToken) {
        Write-Log "No value set for RegistrationToken. Skipping Kasm Desktop Service installation."
    } elseif (-not $ServerId) {
        Write-Log "No value set for ServerId. Skipping Kasm Desktop Service installation."
    } else {
        Write-Log "Desktop service configuration detected"

        if (Test-FileExists -Path $DesktopServiceScript) {
            Write-Log "Invoking $DesktopServiceScript"
            & $DesktopServiceScript -KasmHostname $KasmHostname -ServerId $ServerId -RegistrationToken $RegistrationToken -AwaitDomain $DoJoinDomain
        } else {
            Write-Log "Kasm Desktop Service script does not exist: $DesktopServiceScript" -EntryType "Error"
        } 
    }    
}

Function Invoke-AudioServiceScript {
    if (-not $SkipStartAudioService -and (Test-FileExists -Path $AudioServiceScript)) {
        Write-Log "Audio Service configuration detected"

        if ((Test-FileExists -Path $AudioServiceScript)){
            Write-Log "Invoking $AudioServiceScript"
            & $AudioServiceScript
        } else {
            Write-Log "Audio Service script does not exist: $AudioServiceScript" -EntryType "Error"
        }
    }
}

Function Invoke-DomainJoinAndFSLogixScripts {
    if (-not $DomainName) {
        Write-Log "No value set for Domain. Skipping domain join."
    } elseif (-not $ActiveDirectoryCredential) {
        Write-Log "No value set for ActiveDirectoryCredential. Skipping domain join."
    } else {
        Write-Log "Domain configuration detected"

        if (Test-FileExists -Path $DomainJoinScript) {
            Invoke-InstallFSLogix

            Write-Log "Invoking $DomainJoinScript"
            & $DomainJoinScript -DomainName $DomainName -ActiveDirectoryCredential (ConvertTo-SecureString -String $ActiveDirectoryCredential -AsPlainText -Force) -DnsServers $DnsServers -ServerName $ServerName
        } else {
            Write-Log "Domain join script does not exist: $DomainJoinScript" -EntryType "Error"
        }
    }
}

Function Register-DelayedDesktopServiceScript {
    if (-not $KasmHostname) {
        Write-Log "No value set for KasmHostname. Skipping Kasm Desktop Service installation."
        return
    } elseif (-not $RegistrationToken) {
        Write-Log "No value set for RegistrationToken. Skipping Kasm Desktop Service installation."
        return
    } elseif (-not $ServerId) {
        Write-Log "No value set for ServerId. Skipping Kasm Desktop Service installation."
        return
    }

    $DesktopServiceTaskScript = "$ScriptDirectory\Install-KasmDesktopService-Task.ps1"

    if (Test-FileExists -Path $DesktopServiceTaskScript) {
        Write-Log "Invoking $DesktopServiceTaskScript"
        & $DesktopServiceTaskScript -KasmHostname $KasmHostname -ServerId $ServerId -RegistrationToken $RegistrationToken -KeepTaskActionScripts:$KeepTaskActionScripts
    } else {
        Write-Log "Desktop service task script does not exist: $DesktopServiceTaskScript" -EntryType "Error"
    }
}

Function Invoke-ComputerRename {
    Write-Log "Renaming computer to $ServerName"
    Rename-Computer -NewName $ServerName -Force

    Write-Log "Rebooting to apply computer rename"
    Restart-Computer -Force
}

Function Invoke-InstallFSLogix {
    if ($FSLogix_ProfileLocations) {
        Write-Log "FSLogix configuration detected"

        if (Test-FileExists -Path $FSLogixScript) {
            Write-Log "Invoking $FSLogixScript"
            & $FSLogixScript -ProfileLocations $FSLogix_ProfileLocations -CloudCache $FSLogix_CloudCache -ProfileType $FSLogix_ProfileType
        } else {
            Write-Log "FSLogix install script does not exist: $FSLogixScript" -EntryType "Error"
        }
    }
}

### Main script execution ###

Write-Log "VM initialization script started"

$DoJoinDomain = $DomainName -and $ActiveDirectoryCredential
$DoRenameComputer = $RenameComputer -and $ServerName

& $InstantCloneScript -ComputerRename $DoRenameComputer -DomainJoin $DoJoinDomain

if ($DoJoinDomain) {
    Invoke-DesktopServiceScript
    Invoke-AudioServiceScript
    Invoke-DomainJoinAndFSLogixScripts
} elseif ($DoRenameComputer) {
    Invoke-AudioServiceScript
    Register-DelayedDesktopServiceScript
    Invoke-ComputerRename
} else {
    Invoke-DesktopServiceScript
    Invoke-AudioServiceScript
}

Write-Log "VM initialization script completed"