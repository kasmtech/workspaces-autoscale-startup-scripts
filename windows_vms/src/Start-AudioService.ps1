#ps1_sysnative

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

$ServiceName = "Audiosrv"

if ((Get-Service -Name $ServiceName).Status -ne 'Running') {
    Write-Log "Starting $ServiceName"

    try {
        Set-Service -Name $ServiceName -StartupType Automatic
        Start-Service -Name $ServiceName -ErrorAction Stop
        
        Write-Log "Service $ServiceName started successfully."
    }
    catch {
        Write-Warning "Failed to start service '$ServiceName': $($_.Exception.Message)"
    }
}
