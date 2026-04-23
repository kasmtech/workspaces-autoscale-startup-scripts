Add-Type -AssemblyName System.Net.Http

$ProgressPreference = 'SilentlyContinue'
$KasmEventSource = "kasm_startup_script"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
$KasmLogFile = "$ScriptDirectory\kasm_startup_script.log"

$script:ModuleToken = $null
$script:ModuleKasmHostname = $null
$script:ModuleServerName = $null
$script:ModuleVerifyKasmApiCert = $false

Function Set-LoggingProperties {
    param(
        [Parameter(Mandatory=$false)]
        [string]$KasmHostname,

        [Parameter(Mandatory=$false)]
        [string]$Token,

        [Parameter(Mandatory=$false)]
        [string]$ServerName,

        [switch]$VerifyKasmApiCert
    )

    # Store values in script scope so it’s usable for the entire session
    $script:ModuleKasmHostname = $KasmHostname
    $script:ModuleToken = $Token
    $script:ModuleVerifyKasmApiCert = $VerifyKasmApiCert.IsPresent

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

    if ([string]::IsNullOrEmpty($ModuleToken) -or [string]::IsNullOrEmpty($ModuleKasmHostname)) {
        return
    }

    $levelMap = @{
        "Information" = "INFO"
        "Warning"     = "WARNING"
        "Error"       = "ERROR"
        "Debug"       = "DEBUG"
    }

    $jsonBody = @{
        token = $ModuleToken
        logs = @(
            @{
                host = $ModuleServerName
                application = "windows-startup-script"
                levelname = $levelMap[$EntryType]
                message = $Message
                ingest_date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        )
    } | ConvertTo-Json

    $Url             = "https://$ModuleKasmHostname/api/component_log"
    $MaxRetries      = 3
    $RetryDelay      = 2
    $capturedJson    = $jsonBody
    $capturedLogFile = $KasmLogFile
    $capturedVerify  = $script:ModuleVerifyKasmApiCert

    $null = [System.Threading.Tasks.Task]::Run([System.Action]({
        Add-Type -AssemblyName System.Net.Http

        $handler = [System.Net.Http.HttpClientHandler]::new()
        if (-not $capturedVerify) {
            $handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
        }
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [System.TimeSpan]::FromSeconds(10)

        try {
            for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
                $content  = $null
                $response = $null
                try {
                    $content  = [System.Net.Http.StringContent]::new($capturedJson, [System.Text.Encoding]::UTF8, 'application/json')
                    $response = $client.PostAsync($Url, $content).GetAwaiter().GetResult()
                    $statusCode = [int]$response.StatusCode

                    if ($response.IsSuccessStatusCode) { return }

                    if ($statusCode -ge 400 -and $statusCode -lt 500) {
                        Out-File -InputObject "$(Get-Date -Format o)`tFailed to send log to REST endpoint: HTTP $statusCode" -FilePath $capturedLogFile -Append -Encoding "utf8"
                        return
                    }

                    Out-File -InputObject "$(Get-Date -Format o)`tFailed to send log to REST endpoint: HTTP $statusCode (attempt $attempt of $MaxRetries)" -FilePath $capturedLogFile -Append -Encoding "utf8"
                } catch {
                    $inner  = $_.Exception.InnerException
                    $detail = if ($inner) { "$($_.Exception.Message) -> $($inner.Message)" } else { $_.Exception.Message }
                    Out-File -InputObject "$(Get-Date -Format o)`tFailed to send log to REST endpoint: $detail (attempt $attempt of $MaxRetries)" -FilePath $capturedLogFile -Append -Encoding "utf8"
                } finally {
                    if ($response) { $response.Dispose() }
                    if ($content)  { $content.Dispose()  }
                }

                if ($attempt -lt $MaxRetries) { Start-Sleep -Seconds $RetryDelay }
            }
        } finally {
            $client.Dispose()
            $handler.Dispose()
        }
    }.GetNewClosure()))
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