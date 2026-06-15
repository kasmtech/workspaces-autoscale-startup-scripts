#ps1_sysnative
# TEMPLATE NOTE: This file uses {{ key.path }} tokens replaced by build/template.py at build time.
#   {{ winFsp.installer }}  : NOT a typo, NOT a PS variable -- replaced with value from versions.yaml
#   Do NOT convert {{ }} to $variable or remove the braces.

param(
    [Parameter(Mandatory=$true)]
    [string]$KasmHostname,

    [Parameter(Mandatory=$true)]
    [string]$RegistrationToken,

    [Parameter(Mandatory=$true)]
    [string]$ServerId,

    [Parameter(Mandatory=$false)]
    [bool]$Offline=$false,

    [Parameter(Mandatory=$false)]
    [bool]$Winfsp=$true,

    [Parameter(Mandatory=$false)]
    [bool]$AwaitDomain=$false,

    [switch]$VerifyKasmApiCert
)

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

$WinfspMsi = "{{ winFsp.installer }}"
$WinfspUrl = "{{ winFsp.downloadUrl }}"
$WinfspMsiPattern = "winfsp-*.msi"

$KasmDesktopServiceInstaller = "{{ kasmDesktopService.installer }}"
$KasmDesktopServiceUrl = "{{ kasmDesktopService.downloadUrl }}"
$KasmDesktopServiceInstallerPattern = "kasm_windows_service_installer*.exe"

$KasmInstallPath = "C:\Program Files\Kasm"
$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)

Function Install-Winfsp {
    $InstallerPath = Get-Installer -Directory $ScriptDirectory -Pattern $WinfspMsiPattern -DownloadUrl $WinfspUrl -DownloadFile $WinfspMsi

    if ($InstallerPath) {
        Write-Log "Installing WinFSP"
        Write-Log "Invoking $InstallerPath"

        try {
            Start-Process -FilePath $InstallerPath -ArgumentList '/q' -WorkingDirectory $ScriptDirectory -Wait
        } catch {
            Write-Log "Error installing WinFSP: $($_.Exception.Message)" -EntryType "Error"
            return
        }

        #Remove-Item $InstallerPath -Force
        Write-Log "Installed WinFSP" 
    } else {
        Write-Log "No WinFSP installer found. Skipping WinFSP installation." -EntryType "Warning"
    }
}

Function Stop-KasmDesktopService {
    $service = Get-Service -Name "Kasm" -ErrorAction SilentlyContinue

    if ($service) {
        Write-Log "Attempting to stop Kasm service"
        Stop-Service -Name "Kasm"
        Assert-KasmServiceStatus -Status "Stopped"

    } else {
        Write-Log "No existing Kasm service found"
    }
}

Function Start-KasmDesktopService {
    $service = Get-Service -Name "Kasm" -ErrorAction SilentlyContinue

    if ($service) {
        Write-Log "Attempting to start Kasm service"
        Start-Service -Name "Kasm"
        Assert-KasmServiceStatus -Status "Running"
    } else {
        $message = "No Kasm service found."
        Write-Log $message -EntryType "Error"
        throw $message
    }
}

Function Assert-KasmServiceStatus {
    param(
        [ValidateSet("Running", "Stopped")]
        [Parameter(Mandatory=$true)]
        [string]$Status
    )

    while ($service.Status -ne $Status) {
        Start-Sleep -Seconds 1
        $service = Get-Service -Name "Kasm"
        Write-Log "Service status: $($service.Status)" -EntryType "Debug"

        $Attempts++
        if ($Attempts -ge 30) {
            throw "Timed out waiting for Kasm service to be $Status"
        }
    }

    Write-Log "Kasm service is $Status"
}

Function Install-KasmDesktopService {
    $InstallerPath = Get-Installer -Directory $ScriptDirectory -Pattern $KasmDesktopServiceInstallerPattern -DownloadUrl $KasmDesktopServiceUrl -DownloadFile $KasmDesktopServiceInstaller
    
    if ($InstallerPath) {
        Stop-KasmDesktopService
        
        Write-Log "Installing Kasm Desktop Service"
        Write-Log "Invoking $InstallerPath"

        try {
            $KasmInstallProc = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
            if ($KasmInstallProc.ExitCode -eq 0) {
                Write-Log "Installer completed successfully"
            } else {
                throw $KasmInstallProc.ExitCode
            }
        } catch {
            $ErrorMessage = "Failed to run installer: $_"
            throw $ErrorMessage
        }

        Assert-KasmServiceStatus -Status "Running"

        $service = Get-WmiObject -Class Win32_Service -Filter "Name='Kasm'"
        Write-Log "$($service.Description) successfully installed"
    } else {
        throw "Failed to install desktop service. No installer available."
    }
}

Function Disable-SSLVerification {
    Write-Log "Disabling SSL verification for desktop service registration"

    Add-Type -AssemblyName System.Web.Extensions
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class NoSSLCheckPolicy : ICertificatePolicy {
    public NoSSLCheckPolicy() {}
    public bool CheckValidationResult(
        ServicePoint sPoint, X509Certificate cert,
        WebRequest wRequest, int certProb) {
        return true;
    }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object NoSSLCheckPolicy
}

Function Test-RegistrationToken {
    Write-Log "Verifying registration token with Kasm Manager $KasmHostname"

    $Registration_Attempts=0

    do {
        try {
            $Registration_Attempts++

            Write-Log "Checking Kasm Manager for provisioned server"
            $API_Response = Invoke-RestMethod -Uri "https://$KasmHostname/api/admin/get_server_file_mappings?token=$RegistrationToken" -UseBasicParsing -Method "GET" -ContentType "application/json"

            if ($API_Response -match "Access Denied!") {
                Write-Log "Kasm Manager has not yet provisioned server"
            } else {
                Write-Log "Verified registration token with Kasm Manager $KasmHostname"
                return
            }
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Log "Error while connecting to Kasm: $($_.Exception.Message) ; HTTP Status Code: $statusCode" -EntryType "Error"
        }

        if ($Registration_Attempts -ge 20) {
            $message = "Timed out after waiting for Kasm to provision server"

            Write-Log $message -EntryType "Error"
            throw $message
        }

        Start-Sleep -s 3
    } while ($Registration_Attempts -le 20)    
}

Function Register-KasmDesktopService {
    if (-not $VerifyKasmApiCert) {
        Disable-SSLVerification
    }

    Test-RegistrationToken

    Write-Log "Registering the Windows Service as $ServerId with the Kasm deployment at $KasmHostname"
    $RegisterStdout = "$ScriptDirectory\kasm_register_stdout.txt"
    $RegisterStderr = "$ScriptDirectory\kasm_register_stderr.txt"

    try {
        $AwaitDomainFlag = ""
        if ($AwaitDomain) {
            $AwaitDomainFlag = "--await-domain $true"
            Write-Log "Setting flag --await-domain to $true"
        }

        $KasmRegisterProc = Start-Process -FilePath $KasmInstallPath\agent.exe -ArgumentList "/S --register-host $KasmHostname --register-port 443 --server-id $ServerId --register-token $RegistrationToken $AwaitDomainFlag" -Wait -PassThru -RedirectStandardOutput "$RegisterStdout" -RedirectStandardError "$RegisterStderr"
        if ($KasmRegisterProc.ExitCode -eq 0) {
            if ($AwaitDomain) {
                Write-Log "Registration successfully queued for exeuction after domain join"
            } else {
                Write-Log "Registration completed successfully"
            }
        } else {
            throw $KasmRegisterProc.ExitCode
        }
    } catch {
        $message = "Failed to register agent: $_"
        
        Write-Log $message -EntryType "Error"
        throw $message
    }

    # server restart required after registration
    Stop-KasmDesktopService
    Start-KasmDesktopService
}


### Main script execution ###

Install-Winfsp # Optionally download and install WinFSP, required for Cloud Storage Mapping to work

Install-KasmDesktopService

Register-KasmDesktopService