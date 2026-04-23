# Generates a task action script for Install-KasmDesktopService.ps1 and registers it
# as a scheduled task that runs at next startup as SYSTEM. Used when a computer rename
# reboot is required before the Desktop Service can be installed and registered.

param(
    [Parameter(Mandatory=$false)]
    [string]$KasmHostname,

    [Parameter(Mandatory=$false)]
    [string]$ServerId,

    [Parameter(Mandatory=$false)]
    [string]$RegistrationToken,

    [Parameter(Mandatory=$false)]
    [switch]$KeepTaskActionScripts
)

$TaskName = "KasmDesktopServiceInstall"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

$escapedHostname = $KasmHostname      -replace "'", "''"
$escapedServerId = $ServerId          -replace "'", "''"
$escapedToken    = $RegistrationToken -replace "'", "''"
$keepLiteral     = if ($KeepTaskActionScripts) { '$true' } else { '$false' }

$TaskActionPath = "$ScriptDirectory\Install-KasmDesktopService_TaskAction.ps1"
Set-Content -Path $TaskActionPath -Encoding UTF8 -Value @"
`$ScriptDirectory = Split-Path -Parent `$MyInvocation.MyCommand.Definition
`$keepTaskActionScripts = $keepLiteral
Import-Module "`$ScriptDirectory\Utils.psm1" -Force
if (-not `$keepTaskActionScripts) { Remove-Item `$MyInvocation.MyCommand.Definition -Force -ErrorAction SilentlyContinue }
`$params = @{
    KasmHostname      = '$escapedHostname'
    ServerId          = '$escapedServerId'
    RegistrationToken = '$escapedToken'
}
try {
    & "`$ScriptDirectory\Install-KasmDesktopService.ps1" @params
} catch {
    Write-Log "Failed to invoke Install-KasmDesktopService.ps1: `$_" -EntryType "Error"
} finally {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false -ErrorAction SilentlyContinue
}
"@

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$TaskActionPath`""
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings | Out-Null
    Write-Log "Registered scheduled task: $TaskName"
} catch {
    Write-Log "Failed to register task: $_" -EntryType "Error"
}