# Execute Init-VM.ps1 as a scheduled task running as SYSTEM so it continues running
# after the current session exits. This allows Kasm to immediately add the VM and enable desktop service
# registration. A scheduled task is used for consistency across all providers, though providers using
# Cloudbase Init already execute startup scripts asynchronously. Running as SYSTEM ensures registry
# operations succeed even when no user is logged in.

$TaskName = "KasmStartupScript"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1


# Build argument string
$StartupArgs = $args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
$TaskArgs = @("-ExecutionPolicy", "Bypass", "-File", "`"$($ScriptDirectory)\Init-VM.ps1`"") + $StartupArgs


# Create action for scheduled task
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ($TaskArgs -join ' ')


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
