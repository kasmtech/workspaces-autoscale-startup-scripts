# Windows Autoscale Scripts for Kasm Workspaces

This repository contains PowerShell scripts designed to enable and configure Windows features when utilizing [Windows autoscaling](https://docs.kasm.com/docs/develop/guide/windows/auto_scaled_servers) functionality for [Kasm Workspaces](https://kasm.com/).

## Features
- Kasm Windows Desktop Service - Install and register the Kasm Desktop Service
- Windows Audio Service - Start Windows Audio Service
- Computer Rename - Rename the VM, reboot, and install the Desktop Service post-reboot
- Windows Domain Join - Join the VM to a domain
- DNS Configuration - Configure DNS for the primary network adapter
- FSLogix - Install and configure container profiles
- VMware Instant Clone - Reinitialize cloned VM identity

## Compatibility
![Kasm Workspaces](https://img.shields.io/badge/Kasm%20Workspaces-1.18.1%20%7C%201.18.0-blue?style=flat-square)

| Provider                                                                                                               | ![Windows 10](https://custom-icon-badges.demolab.com/badge/Windows_10-0078D6?logo=windows11&logoColor=white) | ![Windows 11](https://custom-icon-badges.demolab.com/badge/Windows_11-0078D6?logo=windows11&logoColor=white) | ![Windows Server 2022](https://custom-icon-badges.demolab.com/badge/Windows_Server_2022-0078D6?logo=windows11&logoColor=white) | ![Windows Server 2025](https://custom-icon-badges.demolab.com/badge/Windows_Server_2025-0078D6?logo=windows11&logoColor=white) |
|------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------------------------:|
| ![AWS](https://custom-icon-badges.demolab.com/badge/AWS-%23FF9900.svg?logo=aws&logoColor=white)                        |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Microsoft Azure](https://custom-icon-badges.demolab.com/badge/Microsoft%20Azure-0089D6?logo=msazure&logoColor=white) |                          ![Verified](https://img.shields.io/badge/Verified-green)                            |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                   ![Verified](https://img.shields.io/badge/Verified-green)                                     |
| ![Google Cloud](https://img.shields.io/badge/Google%20Cloud-%234285F4.svg?logo=google-cloud&logoColor=white)           |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Harvester](https://img.shields.io/badge/-Harvester-00a383)                                                           |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Nutanix](https://img.shields.io/badge/-Nutanix-024DA1?style=flat&logo=nutanix&logoColor=white)                       |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![OpenStack](https://img.shields.io/badge/-OpenStack-ED1944?style=flat&logo=openstack&logoColor=white)                 |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Oracle Cloud](https://custom-icon-badges.demolab.com/badge/Oracle%20Cloud-F80000?logo=oracle&logoColor=white)        |                          ![N/A](https://img.shields.io/badge/N/A-gray?Color=white)                           |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Proxmox](https://img.shields.io/badge/-Proxmox-E57000?style=flat&logo=proxmox&logoColor=white)                       |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![vSphere](https://img.shields.io/badge/-VMware_vSphere-607078?style=flat&logo=vmware&logoColor=white)                 |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
 
## Dependencies
[![Kasm Desktop Service](https://img.shields.io/badge/Kasm%20Desktop%20Service-develop-blue?style=flat-square)](https://docs.kasmweb.com/docs/develop/guide/windows/windows_service.html#installation)
[![WinFsp](https://img.shields.io/badge/WinFsp-2.0.23075-blue?style=flat-square)](https://winfsp.dev/)
[![FSLogix](https://img.shields.io/badge/FSLogix-latest-blue?style=flat-square)](https://learn.microsoft.com/fslogix/)

This startup script installs additional dependencies required by the configured features.

## Usage
The scripts in this repository are published as a ZIP archive and are intended for use in the **Startup Script** field of a Kasm Workspaces Autoscale Configuration. Features within these scripts are controlled by arguments passed to `Init-VM-Task.ps1`. If a required feature argument is omitted, the corresponding feature will be skipped during installation and configuration at autoscale.

Special placeholder tokens (ex: `{some_variable}`) can be used in the Startup Script field to pass values from the Kasm Workspaces deployment into the Startup Scripts. These tokens are only resolved within the Startup Script field itself and are not replaced in any external scripts that are executed by the Kasm Startup Script.

#### Example Startup Script
```powershell
<powershell>

$Version = "develop"
$StartupScriptArchive = "kasm-windows-startup.zip"
$StartupScriptUrl = "https://kasmweb-build-artifacts.s3.amazonaws.com/kasm-autoscale-scripts/$Version/$StartupScriptArchive"
$WorkingDirectory = "$($Env:Temp)"
$InitScript = "$WorkingDirectory\Init-VM-Task.ps1"
$ProgressPreference = "SilentlyContinue" # improve Invoke-Webrequest performance

Write-Output "`nInitiating Kasm Startup Script"

try {{
    Write-Output "`nDownloading $StartupScriptUrl"
    Invoke-Webrequest -URI $StartupScriptUrl -OutFile "$WorkingDirectory\$StartupScriptArchive"
}} catch {{
    Write-Output "Request failed: $($_.Exception.Message)"
}}

Write-Output "Extracting archive $WorkingDirectory\$StartupScriptArchive"
Expand-Archive -Path "$WorkingDirectory\$StartupScriptArchive" -DestinationPath $WorkingDirectory


### Modify the following arguments to enable desired features ###
Write-Output "Executing $InitScript"
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}"

</powershell>
```

### Kasm Windows Desktop Service
The [Kasm Windows Desktop Service]("https://docs.kasm.com/docs/develop/guide/windows/windows_service") provides additional capabilities to users that are connected to the desktop through Kasm Workspaces. To utilize these features the Desktop Service must be installed and registered with Kasm Workspaces. 

| Varible              | Required     | Type   |  Description     |
|----------------------|--------------|--------|-----------------|
| $KasmHostname        | Required     | string | The resolvable hostname, IP, or FQDN of the KASM API server. If used in the Startup Script, the token `{upstream_auth_address}` will be replaced with the value of "Zone" > "Upstream Auth Address" from the autoscale configuration's zone. |
| $RegistrationToken   | Required     | string | The registration token (JWT) created by Kasm for the newly created server. If used in the Startup Script, the token `{checkin_jwt}` will be replaced with a Kasm-generated registration token that is valid for 4 hours. |
| $ServerId            | Required     | string | The UUID created by Kasm for the new server, found in the Server's "Server Id" field in the Kasm UI. If used in the Startup Script, the token `{server_id}` will be replaced with the correct value automatically. |

#### Example - Install and Register Kasm Windows Desktop Service Only  
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}"
```

### Windows Audio Service
This startup script package will automatically enable the Windows Audio service if disabled. This is useful when using a Windows Server OS for VDI as the Auidsrv is not started automatically.

| Varible                | Required     | Type   | Description               |
|------------------------|--------------|--------|---------------------------|
| $SkipStartAudioService | Optional     | switch | Skip audio service setup. |

#### Example - Kasm Windows Desktop Service without enabling Audiosrv
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -SkipStartAudioService
```

### Domain Join
Connect a computer to an Active Directory domain. Additional setup information for domain joining Kasm autoscaled VMs can be found [here](https://docs.kasm.com/docs/develop/guide/windows/auto_scaled_servers).

| Varible                    | Required     | Type   | Description                                                                                                                                                                                                                                                                                                                          |
|----------------------------|--------------|--------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| $DomainName                | Requried     | string | The Windows Domain that the VM will join. If used in the Startup Script, the token `{domain}` will be replaced with the domain constructed from the "Authentication" > "LDAP Configuration" > "Search Base" from the LDAP Config specified in the Autoscale Config.                                                                  |
| $ActiveDirectoryCredential | Required     | string | The account credential used to join the computer to the domain. If used in the Startup Script, the token `{ad_join_credential}` will be replaced with an appropriate value generated by Kasm and set on the machine.                                                                                                                 |
| $DnsServers                | Optional     | string[] | To join the Windows VM to the domain, it is necessary for the VM to be able to resolve the domain controller. If DNS is not preconfigured as part of the VM image, then this varible can be used to configure DNS to point to the domain controller.                                                                                 |
| $ServerName                | Optional     | string | Sets the VM hostname to this value if necessary. Token `{server_hostname}` represents the name of the computer object added to Active Directory by Kasm. If your Windows template or hypervisor are not utilizing CloudBase-Init, it might be necessary to rename the computer to match the Active Directory record created by Kasm. |

#### Example - Configure DNS, Rename Computer to match Active Directory Entry, and Join Domain
```powershell
& $InitScript `
  -DomainName "{domain}" `
  -ActiveDirectoryCredential "{ad_join_credential}" `
  -DnsServers "10.0.0.52" `
  -ServerName "{server_hostname}"
```

### Computer Rename
For scenarios where a VM needs to be renamed without joining a domain (such as VMware Instant Clones), the startup script can rename the computer, reboot, and then install the Kasm Desktop Service automatically after the reboot via a scheduled task.

> **Note:** This flow is mutually exclusive with Domain Join. If domain join arguments are provided, the rename-and-reboot flow is skipped and the standard domain join process handles renaming.

| Variable           | Required | Type   | Description                                                                                                                                                                                                                     |
|--------------------|----------|--------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| $RenameComputer    | Required | switch | Enables computer renaming.                                                                                                                                                                                                      |
| $ServerName        | Required | string | The new hostname to assign to the VM. If used in the Startup Script, the token `{server_hostname}` will be replaced with the computer object name created by Kasm. If this value is empty, the rename flow is skipped entirely. |
| $KasmHostname      | Required | string | Required for the Desktop Service installation that runs post-reboot.                                                                                                                                                            |
| $RegistrationToken | Required | string | Required for the Desktop Service installation that runs post-reboot.                                                                                                                                                            |
| $ServerId          | Required | string | Required for the Desktop Service installation that runs post-reboot.                                                                                                                                                            |

#### Example - Rename Computer and Install Desktop Service Post-Reboot
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -ServerName "{server_hostname}" `
  -RenameComputer
```

### VMware Instant Clone
When VMware Instant Clone is detected, the startup script automatically reinitializes the cloned VM's identity before any other configuration runs. This step is skipped silently on non-Instant Clone VMs.

The following actions are performed on every Instant Clone:
- **Machine GUID regeneration** — generates a new `MachineGuid` in the registry to ensure each clone has a unique cryptographic identity
- **NetBIOS disable** — disables NetBIOS over TCP/IP on all network interfaces to prevent broadcast conflicts between clones; skipped when Computer Rename or Domain Join is configured (can also be skipped with `$SkipDisableNetBios`)
- **DNS cache flush** — clears the DNS client cache to prevent stale resolutions carried over from the parent VM; skipped when Computer Rename or Domain Join is configured since a reboot is imminent and the network stack reinitializes on restart.

| Variable            | Required | Type   | Description                              |
|---------------------|----------|--------|------------------------------------------|
| $SkipDisableNetBios | Optional | switch | Skip disabling NetBIOS on all interfaces. |

#### Example - Instant Clone with NetBIOS Disable Skipped
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -SkipDisableNetBios
```

### FSLogix

| Varible                   | Required | Type | Description     |
|---------------------------|----------|------|------------|
| $FSLogix_ProfileLocations | Required | string | Virtual Hard Disk or Cloud Cache location(s) for FSLogix container profile storage. |
| $FSLogix_CloudCache       | Optional | bool   | Enables FSLogix [Cloud Cache](https://learn.microsoft.com/en-us/fslogix/concepts-fslogix-cloud-cache) feature. Default is false. |
| $FSLogix_ProfileType      | Optional | int    | Sets the FSLogix profile type. Default is 3, which supports cocurrent writable sessions. Use 1 for a single writable session. |

#### Example - Join Domain, Install FSLogix and Configure Virtual Hard Disk Location
```powershell
& $InitScript `
  -DomainName "{domain}" `
  -ActiveDirectoryCredential "{ad_join_credential}" `
  -ServerName "{server_hostname}" `
  -FSLogix_ProfileLocations "\\WIN-AD\FSLogixProfiles"
```

## Troubleshooting

| Variable               | Required | Type   | Description                                                                                                                                      |
|------------------------|----------|--------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| $KeepTaskActionScripts | Optional | switch | Retains the generated task action scripts and their embedded argument values on disk after execution for manual inspection and re-execution. |

#### Example - Retain Task Action Scripts for Inspection and Manual Testing
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -KeepTaskActionScripts
```

## Logging
The scripts in this repository write all output as both Windows Events that can be viewed in Windows Event Viewer and text based logs that can be found at `C:\Users\cloudbase-init\AppData\Local\Temp\kasm_startup_script.log`. The Kasm Desktop Service installer executable does not send its own logs to the Windows Event Viewer, but its text based logs can be found in `C:\Users\cloudbase-init\AppData\Local\Temp\kasm_agent_install-{timestamp}.log`, where `{timestamp}` takes the form of `yymmdd-hhmmss`, e.g. `kasm_agent_install-20251016-123456.log`.

When available, Kasm Windows Autoscaling uses Cloudbase-Init to execute the configured Startup Scripts. For autoscale errors that occur prior to invoking `Init-VM-Task.ps1`, refer to the Cloudbase logs found at `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log`.



