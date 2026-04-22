# Execute Init-VM.ps1 as a scheduled task running as SYSTEM so it continues running
# after the current session exits. This allows Kasm to immediately add the VM and enable desktop service
# registration. A scheduled task is used for consistency across all providers, though providers using
# Cloudbase Init already execute startup scripts asynchronously. Running as SYSTEM ensures registry
# operations succeed even when no user is logged in.

param(
    # Retains the generated task action scripts and their input arguments on disk after execution
    # to allow manual inspection and re-execution for troubleshooting purposes.
    [switch]$KeepTaskActionScripts
)

$TaskName = "KasmStartupScript"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1


# Build a wrapper script that calls Init-VM.ps1 with the provided values
$paramLines = @()
$i = 0
while ($i -lt $args.Count) {
    $arg     = $args[$i]
    $nextArg = if ($i + 1 -lt $args.Count) { $args[$i + 1] } else { $null }
    $nextIsValue = $nextArg -and ($nextArg -notmatch '^-')

    if ($arg -match '^-(.+)$') {
        $name = $Matches[1]
        if ($nextIsValue) {
            if ($nextArg -eq 'True') {
                $paramLines += "    $name = `$true"
                $i += 2
            } elseif ($nextArg -eq 'False') {
                $i += 2
            } else {
                $escaped = $nextArg -replace "'", "''"
                $paramLines += "    $name = '$escaped'"
                $i += 2
            }
        } else {
            $paramLines += "    $name = `$true"
            $i++
        }
    } else {
        $i++
    }
}

if ($KeepTaskActionScripts) { $paramLines += "    KeepTaskActionScripts = `$true" }

$paramsBlock = $paramLines -join [Environment]::NewLine
$keepTaskActionScriptsLiteral = if ($KeepTaskActionScripts) { '$true' } else { '$false' }
$WrapperPath = "$ScriptDirectory\Init-VM_TaskAction.ps1"
Set-Content -Path $WrapperPath -Encoding UTF8 -Value @"
`$ScriptDirectory = Split-Path -Parent `$MyInvocation.MyCommand.Definition
`$keepTaskActionScripts = $keepTaskActionScriptsLiteral
Import-Module "`$ScriptDirectory\Utils.psm1" -Force
`$params = @{
$paramsBlock
}
try {
    & "`$ScriptDirectory\Init-VM.ps1" @params
} catch {
    Write-Log "Failed to invoke Init-VM.ps1: `$_" -EntryType "Error"
} finally {
    if (-not `$keepTaskActionScripts) { Remove-Item `$MyInvocation.MyCommand.Definition -Force -ErrorAction SilentlyContinue }
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

$TaskResult = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
if ($TaskResult -ne 0) {
    Write-Log "Scheduled task exited with code $TaskResult" -EntryType "Error"
}


# Remove the task
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Log "Unregistered scheduled task"
} catch {
    Write-Log "Failed to unregister task: $_" -EntryType "Error"
}
