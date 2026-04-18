$ProgressPreference = 'SilentlyContinue'
$KasmEventSource = "kasm_startup_script"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
$KasmLogFile = "$ScriptDirectory\kasm_startup_script.log"

$script:ModuleToken = $null
$script:ModuleKasmHostname = $null
$script:ModuleServerName = $null
$script:ModuleSkipCertCheck = $true

Function Set-LoggingProperties {
    param(
        [Parameter(Mandatory=$false)]
        [string]$KasmHostname,

        [Parameter(Mandatory=$false)]
        [string]$Token,

        [Parameter(Mandatory=$false)]
        [string]$ServerName,

        [Parameter(Mandatory=$false)]
        [bool]$SkipCertificateCheck = $true
    )

    # Store values in script scope so it’s usable for the entire session
    $script:ModuleKasmHostname = $KasmHostname
    $script:ModuleToken = $Token
    $script:ModuleSkipCertCheck = $SkipCertificateCheck

    if ($null -eq $ServerName -or $ServerName -eq "") {
        # Set ServerName to computer name if not set
        $script:ModuleServerName = $env:COMPUTERNAME
    } else {
        $script:ModuleServerName = $ServerName
    }
}

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
        
        [ValidateSet("Information", "Warning", "Error", "Debug")]
        [Parameter(Mandatory=$false)][string]$EntryType="Information"
    )

    $Timestamp = $(Get-Date -Format o)

    try {
        # EventLog does not support Debug; map it to Information
        $EventLogEntryType = if ($EntryType -eq "Debug") { "Information" } else { $EntryType }
        Write-EventLog -LogName $LogName -Source $Source -EventID $EventID -EntryType $EventLogEntryType -Message $Message
    } catch {
        $ErrorLogObj = "$Timestamp`tUnable to write to eventlog:"
        Out-File -InputObject $ErrorLogObj -FilePath $LogFile -Append -Encoding "utf8"
    } finally {
        $LogObj = "$Timestamp`t$Message"

        # Write to file
        Out-File -InputObject $LogObj -FilePath $LogFile -Append -Encoding "utf8"

        # Send to Kasm central logging
        Send-KasmLog -Message $Message -EntryType $EntryType

        # Write to console if running interactively
        if ($Host.Name -ne 'ServerHost') {
            Write-Host $LogObj
        }
    }
}

Function Send-KasmLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("Information", "Warning", "Error", "Debug")]
        [Parameter(Mandatory=$false)]
        [string]$EntryType = "Information"
    )

    if ([string]::IsNullOrEmpty($ModuleToken) -or [string]::IsNullOrEmpty($ModuleKasmhostname)) {
        # required field missing, skipping request."
        return
    }

    $levelMap = @{
        "Information" = "INFO"
        "Warning"     = "WARNING"
        "Error"       = "ERROR"
        "Debug"       = "DEBUG"
    }

    $Url = "https://$ModuleKasmHostname/api/component_log"

    try {
        # Create the data structure
        $jsonBody = @{
            token = $ModuleToken
            logs = @(
                @{
                    host = $ModuleServerName
                    application = "windows-startup-script"
                    levelname = $levelMap[$EntryType]
                    message = $Message
                }
            )
        } | ConvertTo-Json

        # Build HttpClient with optional cert bypass and 10s timeout
        if ($script:ModuleSkipCertCheck) {
            $handler = [System.Net.Http.HttpClientHandler]::new()
            $handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
            $client = [System.Net.Http.HttpClient]::new($handler)
        } else {
            $client = [System.Net.Http.HttpClient]::new()
        }
        $client.Timeout = [System.TimeSpan]::FromSeconds(10)

        $content = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, 'application/json')

        # Non-blocking request to Kasm API, returns immediately without blocking the startup script
        $null = $client.PostAsync($Url, $content)
    } catch {
        $ErrorMsg = "$(Get-Date -Format o)`tFailed to send log to REST endpoint: $($_.Exception.Message)"
        Out-File -InputObject $ErrorMsg -FilePath $KasmLogFile -Append -Encoding "utf8"
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