# Execute Init-VM.ps1 as a scheduled task running as SYSTEM so it continues running
# after the current session exits. This allows Kasm to immediately add the VM and enable desktop service
# registration. A scheduled task is used for consistency across all providers, though providers using
# Cloudbase Init already execute startup scripts asynchronously. Running as SYSTEM ensures registry
# operations succeed even when no user is logged in.

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

    [switch]$SkipStartAudioService,

    [switch]$SkipDisableNetBios,

    [switch]$RenameComputer,

    [switch]$KeepTaskActionScripts,

    [switch]$VerifyKasmApiCert
)

$TaskName = "KasmStartupScript"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1


$escapedDomainName               = $DomainName               -replace "'", "''"
$escapedActiveDirectoryCredential = $ActiveDirectoryCredential -replace "'", "''"
$escapedKasmHostname             = $KasmHostname             -replace "'", "''"
$escapedRegistrationToken        = $RegistrationToken        -replace "'", "''"
$escapedServerId                 = $ServerId                 -replace "'", "''"
$escapedServerName               = $ServerName               -replace "'", "''"
$escapedFSLogixProfileLocations  = $FSLogix_ProfileLocations  -replace "'", "''"
$escapedFSLogixCloudCache        = $FSLogix_CloudCache        -replace "'", "''"
$escapedFSLogixProfileType       = $FSLogix_ProfileType       -replace "'", "''"

$dnsServersLiteral = if ($DnsServers) {
    $items = $DnsServers | ForEach-Object { "'$($_ -replace "'", "''")'" }
    "@($($items -join ', '))"
} else { '@()' }

$skipAudioLiteral   = if ($SkipStartAudioService) { '$true' } else { '$false' }
$skipNetBiosLiteral = if ($SkipDisableNetBios)    { '$true' } else { '$false' }
$renameLiteral      = if ($RenameComputer)        { '$true' } else { '$false' }
$keepLiteral        = if ($KeepTaskActionScripts) { '$true' } else { '$false' }
$verifyLiteral      = if ($VerifyKasmApiCert)     { '$true' } else { '$false' }

$WrapperPath = "$ScriptDirectory\Init-VM_TaskAction.ps1"
Set-Content -Path $WrapperPath -Encoding UTF8 -Value @"
`$ScriptDirectory = Split-Path -Parent `$MyInvocation.MyCommand.Definition
`$keepTaskActionScripts = $keepLiteral
Import-Module "`$ScriptDirectory\Utils.psm1" -Force
if (-not `$keepTaskActionScripts) { Remove-Item `$MyInvocation.MyCommand.Definition -Force -ErrorAction SilentlyContinue }
`$params = @{
    DomainName                = '$escapedDomainName'
    ActiveDirectoryCredential = '$escapedActiveDirectoryCredential'
    DnsServers                = $dnsServersLiteral
    KasmHostname              = '$escapedKasmHostname'
    RegistrationToken         = '$escapedRegistrationToken'
    ServerId                  = '$escapedServerId'
    ServerName                = '$escapedServerName'
    FSLogix_ProfileLocations  = '$escapedFSLogixProfileLocations'
    FSLogix_CloudCache        = '$escapedFSLogixCloudCache'
    FSLogix_ProfileType       = '$escapedFSLogixProfileType'
    SkipStartAudioService     = $skipAudioLiteral
    SkipDisableNetBios        = $skipNetBiosLiteral
    RenameComputer            = $renameLiteral
    KeepTaskActionScripts     = $keepLiteral
    VerifyKasmApiCert         = $verifyLiteral
}
try {
    & "`$ScriptDirectory\Init-VM.ps1" @params
} catch {
    Write-Log "Failed to invoke Init-VM.ps1: `$_" -EntryType "Error"
}
"@


# Create action for scheduled task
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$WrapperPath`""


# Register the task as SYSTEM, scheduled to run once
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -RunLevel Highest -User "SYSTEM" -Force -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)) | Out-Null
    Write-Log "Registered scheduled task: $TaskName"
} catch {
    Write-Log "Failed to register task: $_" -EntryType "Error"
}


# Run it immediately
try {
    Start-ScheduledTask -TaskName $TaskName
    Write-Log "Started scheduled task"
} catch {
    Write-Log "Failed to start task: $_" -EntryType "Error"
}


# Give it a moment to start
Start-Sleep -Seconds 5


# Remove the task
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Log "Unregistered scheduled task"
} catch {
    Write-Log "Failed to unregister task: $_" -EntryType "Error"
}