$ProgressPreference = 'SilentlyContinue'
$KasmEventSource = "kasm_startup_script"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
$KasmLogFile = "$ScriptDirectory\kasm_startup_script.log"

Function New-EventLogSource {
    # Create eventlog source for logging
    if(-not [System.Diagnostics.EventLog]::SourceExists($KasmEventSource)) {
        try {
            New-EventLog -LogName "Application" -Source $KasmEventSource
        } catch {
            Write-Log "Failed to create Kasm Startup Script eventlog source" -EntryType "Warning"
        }
    }
}

Function Write-Log {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile=$KasmLogFile,
        
        [Parameter(Mandatory=$false)]
        [string]$LogName="Application",
        
        [Parameter(Mandatory=$false)]
        [string]$Source=$KasmEventSource,
        
        [Parameter(Mandatory=$false)]
        [int]$EventID=1000,
        
        [ValidateSet("Information", "Warning", "Error")]
        [Parameter(Mandatory=$false)][string]$EntryType="Information"
    )

    $Timestamp = $(Get-Date -Format o)  

    try {
        Write-EventLog -LogName $LogName -Source $Source -EventID $EventID -EntryType $EntryType -Message $Message
    } catch {
        $ErrorLogObj = "$Timestamp`tUnable to write to eventlog:"
        Out-File -InputObject $ErrorLogObj -FilePath $LogFile -Append -Encoding "utf8"
    } finally {
        $LogObj = "$Timestamp`t$Message"
        Out-File -InputObject $LogObj -FilePath $LogFile -Append -Encoding "utf8"

        # Write to console if running interactively
        if ($Host.Name -ne 'ServerHost') {
            Write-Host $LogObj
        }
    }
}

Function Get-FileByPattern {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Directory,

        [Parameter(Mandatory=$true)]
        [string]$Pattern
    )

    # Check for installers in working directory
    $Files = Get-ChildItem -Path $Directory -Name $Pattern -ErrorAction SilentlyContinue

    if ($Files) {
        # Handle both single file and array of files
        if ($Files -is [array]) {
            # Using first file found if multiple matching
            $FileName = $Files[0] 
        } else {
            $FileName = $Files
        }

        return Join-Path $Directory $FileName
    }

    return
}

Function Get-Installer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Directory,

        [Parameter(Mandatory=$true)]
        [string]$Pattern,

        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl,

        [Parameter(Mandatory=$true)]
        [string]$DownloadFile
    )

    # Check for installers in working directory
    $Installer = Get-FileByPattern -Directory $Directory -Pattern $Pattern

    if ($Installer) {
        Write-Log "Installer found: $Installer"
        return $Installer
    } 
    
    if (-not $Offline) {
        Write-Log "Downloading $DownloadUrl"

        try {
            $Installer = "$Directory\$DownloadFile"

            Invoke-Webrequest -Uri $DownloadUrl -OutFile $Installer
            Write-Log "Downloaded $Installer"

            return $Installer
        } catch {
            Write-Log "Failed to download $DownloadUrl $_" -EntryType "Warning"
            return
        }
    }
    
    return
}

function Test-FileExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Test-Path -Path $Path -PathType Leaf
}

New-EventLogSource

# Ensure we're only making connections over TLS 1.2 or 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12,[Net.SecurityProtocolType]::Tls13