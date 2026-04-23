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


# Serialize $args into a clean argv array, normalizing bool-as-string values
# (e.g. "-Switch True/False") and preserving multi-value parameters
# (e.g. -DnsServers 1.1.1.1 8.8.8.8) so PowerShell's own binder handles them.
$argv = [System.Collections.Generic.List[string]]::new()
$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    if ($arg -match '^-') {
        $argv.Add($arg)
        $i++
        while ($i -lt $args.Count -and $args[$i] -notmatch '^-') {
            $val = $args[$i]
            if ($val -eq 'True') {
                $i++  # switch already added; drop 'True'
            } elseif ($val -eq 'False') {
                $argv.RemoveAt($argv.Count - 1)  # remove switch; drop 'False'
                $i++
            } else {
                $argv.Add($val)
                $i++
            }
        }
    } else {
        $i++
    }
}
if ($KeepTaskActionScripts) { $argv.Add('-KeepTaskActionScripts') }

$argvLines = $argv | ForEach-Object { "    '$($_ -replace "'", "''")'" }
$argvBlock = $argvLines -join ",$([Environment]::NewLine)"
$keepTaskActionScriptsLiteral = if ($KeepTaskActionScripts) { '$true' } else { '$false' }
$WrapperPath = "$ScriptDirectory\Init-VM_TaskAction.ps1"
Set-Content -Path $WrapperPath -Encoding UTF8 -Value @"
`$ScriptDirectory = Split-Path -Parent `$MyInvocation.MyCommand.Definition
`$keepTaskActionScripts = $keepTaskActionScriptsLiteral
Import-Module "`$ScriptDirectory\Utils.psm1" -Force
`$argv = @(
$argvBlock
)
try {
    & "`$ScriptDirectory\Init-VM.ps1" @argv
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
