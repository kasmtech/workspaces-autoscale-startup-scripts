#ps1_sysnative
# TEMPLATE NOTE: This file uses {{ key.path }} tokens replaced by build/template.py at build time.
#   {{ fsLogix.installer }}  : NOT a typo, NOT a PS variable -- replaced with value from versions.yaml
#   Do NOT convert {{ }} to $variable or remove the braces.

param(
    [Parameter(Mandatory=$true)]
    [string]$ProfileLocations,
    
    [Parameter(Mandatory=$false)]
    [string]$CloudCache=$false,

    [Parameter(Mandatory=$false)]
    [int]$ProfileType = 3 # https://learn.microsoft.com/en-us/fslogix/concepts-multi-concurrent-connections#profile-container-vhdx-differencing-disks
)

$ScriptDirectory = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)
Import-Module $ScriptDirectory\Utils.psm1

$FslogixArchive = "{{ fsLogix.installer }}"
$FslogixArchiveUrl = "{{ fsLogix.downloadUrl }}"
$FslogixArchivePattern = "FSLogix_*.zip"

$InstallDirectory = "C:\FSLogix"
$Installer = "$InstallDirectory\x64\Release\FSLogixAppsSetup.exe"

Function Install-FSLogix {
    $ArchivePath = Get-Installer -Directory $ScriptDirectory -Pattern $FslogixArchivePattern -DownloadUrl $FslogixArchiveUrl -DownloadFile $FslogixArchive

    if ($ArchivePath) {
        Write-Log "Expanding $ArchivePath to $InstallDirectory"
        Expand-Archive -Path $ArchivePath -DestinationPath $InstallDirectory

        Write-Log "Invoking FSLogix installer $Installer"
        Start-Process -FilePath $Installer -ArgumentList "/install /quiet /norestart" -Wait

        Write-Log "FSLogix installed"

        return $true
    }

    return $false
}

Function Set-ProfileContainersConfiguration {    
    $RegistryPath = 'HKLM:\SOFTWARE\FSLogix\Profiles'

    # Ensure the key exists
    New-Item -Path $RegistryPath -Force | Out-Null

    if ($CloudCache) {
        # https://learn.microsoft.com/en-us/fslogix/concepts-configuration-examples#example-2-standard--high-availability-cloud-cache

        Write-Log "Setting FSLogix profile container configuration for CCD. CCDLocations: $ProfileLocations"

        New-ItemProperty -Path $RegistryPath -Name CCDLocations -PropertyType string -value $ProfileLocations -Force
        New-ItemProperty -Path $RegistryPath -Name ClearCacheOnLogoff -PropertyType dword -Value 1 -Force
        New-ItemProperty -Path $RegistryPath -Name HealthyProvidersRequiredForRegister -PropertyType dword -Value 1 -Force
    } else {
        # https://learn.microsoft.com/en-us/fslogix/concepts-configuration-examples#configuration-items-standard

        Write-Log "Setting FSLogix profile container configuration for VHD. VHDLocations: $ProfileLocations"

        New-ItemProperty -Path $RegistryPath -Name VHDLocations -PropertyType string -value $ProfileLocations -Force 
    }

    New-ItemProperty -Path $RegistryPath -Name ProfileType -PropertyType dword -Value $ProfileType -Force
    New-ItemProperty -Path $RegistryPath -Name Enabled -PropertyType dword -Value 1 -Force
    New-ItemProperty -Path $RegistryPath -Name DeleteLocalProfileWhenVHDShouldApply -PropertyType dword -Value 1 -Force
    New-ItemProperty -Path $RegistryPath -Name FlipFlopProfileDirectoryName -PropertyType dword -Value 1 -Force
    New-ItemProperty -Path $RegistryPath -Name LockedRetryCount -PropertyType dword -Value 3 -Force
    New-ItemProperty -Path $RegistryPath -Name LockedRetryInterval -PropertyType dword -Value 15 -Force
    New-ItemProperty -Path $RegistryPath -Name ReAttachIntervalSeconds -PropertyType dword -Value 15 -Force
    New-ItemProperty -Path $RegistryPath -Name ReAttachRetryCount -PropertyType dword -Value 3 -Force
    New-ItemProperty -Path $RegistryPath -Name SizeInMBs -PropertyType dword -Value 30000 -Force
    New-ItemProperty -Path $RegistryPath -Name VolumeType -PropertyType string -Value vhdx -Force
    
    Write-Log "FSLogix profile containers configured."
}

if (Install-FSLogix) {
    Set-ProfileContainersConfiguration
}