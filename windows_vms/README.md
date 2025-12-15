# Windows Autoscale Scripts for Kasm Workspaces

This repository contains PowerShell scripts designed to enable and configure Windows features when utilizing [Windows autoscaling](https://docs.kasm.com/docs/guide/windows/auto_scaled_servers.html) functionality for [Kasm Workspaces](https://kasmweb.com/).

## Features
- Kasm Windows Desktop Service - Install and register the Kasm Desktop Service
- Windows Audio Service - Start Windows Audio Service
- Windows Domain Join - Join the VM to a domain
- DNS Configuration - Configure DNS for the primary network adapter
- FSLogix - Install and configure container profiles

## Compatibility
![Kasm Workspaces](https://img.shields.io/badge/Kasm%20Workspaces-1.18.1%20%7C%201.18.0-blue?style=flat-square)

| Provider                                                                                                               | ![Windows 10](https://custom-icon-badges.demolab.com/badge/Windows_10-0078D6?logo=windows11&logoColor=white) | ![Windows 11](https://custom-icon-badges.demolab.com/badge/Windows_11-0078D6?logo=windows11&logoColor=white) | ![Windows Server 2022](https://custom-icon-badges.demolab.com/badge/Windows_Server_2022-0078D6?logo=windows11&logoColor=white) | ![Windows Server 2025](https://custom-icon-badges.demolab.com/badge/Windows_Server_2025-0078D6?logo=windows11&logoColor=white) |
|------------------------------------------------------------------------------------------------------------------------|:------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------------------------:|:------------------------------------------------------------------------------------------------------------------------------:|
| ![AWS](https://custom-icon-badges.demolab.com/badge/AWS-%23FF9900.svg?logo=aws&logoColor=white)                        |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Microsoft Azure](https://custom-icon-badges.demolab.com/badge/Microsoft%20Azure-0089D6?logo=msazure&logoColor=white) |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Google Cloud](https://img.shields.io/badge/Google%20Cloud-%234285F4.svg?logo=google-cloud&logoColor=white)           |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Harvester](https://img.shields.io/badge/-Harvester-00a383)                                                           |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Nutanix](https://img.shields.io/badge/-Nutanix-024DA1?style=flat&logo=nutanix&logoColor=white)                       |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![OpenStack](https://img.shields.io/badge/-OpenStack-ED1944?style=flat&logo=openstack&logoColor=white)                 |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Oracle Cloud](https://custom-icon-badges.demolab.com/badge/Oracle%20Cloud-F80000?logo=oracle&logoColor=white)        |                          ![N/A](https://img.shields.io/badge/N/A-gray?Color=white)                           |                                ![N/A](https://img.shields.io/badge/N/A-gray)                                 |                                    ![Verified](https://img.shields.io/badge/Verified-green)                                    |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![Proxmox](https://img.shields.io/badge/-Proxmox-E57000?style=flat&logo=proxmox&logoColor=white)                       |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                           ![Verified](https://img.shields.io/badge/Verified-green)                           |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
| ![vSphere](https://img.shields.io/badge/-VMware_vSphere-607078?style=flat&logo=vmware&logoColor=white)                 |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                       ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                        |                                  ![Not Verified](https://img.shields.io/badge/Verified-green)                                  |                                ![Not Verified](https://img.shields.io/badge/Not_Verified-gray)                                 |
 
## Dependencies
[![Kasm Desktop Service](https://img.shields.io/badge/Kasm%20Desktop%20Service-1.7.c54746a56-blue?style=flat-square)](https://docs.kasm.com/docs/guide/windows/windows_service.html#installation)
[![WinFsp](https://img.shields.io/badge/WinFsp-2.0.23075-blue?style=flat-square)](https://winfsp.dev/)
[![FSLogix](https://img.shields.io/badge/FSLogix-latest-blue?style=flat-square)](https://learn.microsoft.com/fslogix/)

This startup script installs additional dependencies required by the configured features.

## Usage
The scripts in this repository are published as a ZIP archive and are intended for use in the **Startup Script** field of a Kasm Workspaces Autoscale Configuration. Features within these scripts are controlled by arguments passed to `Init-VM-Task.ps1`. If a required feature argument is omitted, the corresponding feature will be skipped during installation and configuration at autoscale.

Special placeholder tokens (ex: `{some_variable}`) can be used in the Startup Script field to pass values from the Kasm Workspaces deployment into the Startup Scripts. These tokens are only resolved within the Startup Script field itself and are not replaced in any external scripts that are executed by the Kasm Startup Script.

#### Example Startup Script
```powershell
#ps1_sysnative

$StartupScriptArchive = "kasm-windows-startup.zip"
$StartupScriptUrl = "https://kasmweb-build-artifacts.s3.amazonaws.com/kasm-autoscale-scripts/1.18.1/$StartupScriptArchive"
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


### INSERT EXECUTION COMMAND HERE ###
```

#### Example Execution Command
```powershell
Write-Output "Executing $InitScript"
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -DomainName "{domain}" `
  -ActiveDirectoryCredential "{ad_join_credential}" `
  -DnsServers "10.0.0.52" `
  -ServerName "{server_hostname}" `
  -FSLogix_ProfileLocations "\\WIN-AD\FSLogixProfiles"
```

### Kasm Windows Desktop Service
The [Kasm Windows Desktop Service]("https://docs.kasm.com/docs/guide/windows/windows_service.html") provides additional capabilities to users that are connected to the desktop through Kasm Workspaces. To utilize these features the Desktop Service must be installed and registered with Kasm Workspaces. 

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

| Varible                | Required     | Type |  Description     |
|------------------------|--------------|------|------------------|
| $StartAudioService     | Optional     | bool | Enables the Windows Audio service and sets startup to Automatic. Default is true. |

#### Example - Kasm Windows Desktop Service without enabling Audiosrv
```powershell
& $InitScript `
  -KasmHostname "{upstream_auth_address}" `
  -RegistrationToken "{checkin_jwt}" `
  -ServerId "{server_id}" `
  -StartAudioService $false
```

### Domain Join
Connect a computer to an Active Directory domain. Additional setup information for domain joining Kasm autoscaled VMs can be found [here](https://docs.kasm.com/docs/guide/windows/auto_scaled_servers#auto-join-active-directory).

| Varible                    | Required     | Type   | Description     |
|----------------------------|--------------|--------|-----------------|
| $DomainName                | Requried     | string | The Windows Domain that the VM will join. If used in the Startup Script, the token `{domain}` will be replaced with the domain constructed from the "Authentication" > "LDAP Configuration" > "Search Base" from the LDAP Config specified in the Autoscale Config. |
| $ActiveDirectoryCredential | Required     | string | The account credential used to join the computer to the domain. If used in teh Startup Script, the token `{ad_join_credential}` will be replaced with an appropriate value generated by Kasm and set on the machine. |
| $DnsServers                | Optional     | string | To join the Windows VM to the domain, it is necessary for the VM to be able to resolve the domain controller. If DNS is not preconfigured as part of the VM image, then this varible can be used to configure DNS to point to the domain controller. |
| $ServerName                | Optional     | string | Sets the VM hostname to this value if necessary. Token `{server_hostname}` represents the name of the computer object added to Active Directory by Kasm. If your Windows template or hypervisor are not utilizing CloudBase-Init, it might be necessary to rename the computer to match the Active Directory record created by Kasm. |

#### Example - Configure DNS, Rename Computer to match Active Directory Entry, and Join Domain
```powershell
& $InitScript `
  -DomainName "{domain}" `
  -ActiveDirectoryCredential "{ad_join_credential}" `
  -DnsServers "10.0.0.52" `
  -ServerName "{server_hostname}"
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

## Logging
The scripts in this repository write all output as both Windows Events that can be viewed in Windows Event Viewer and text based logs that can be found at `C:\Users\cloudbase-init\AppData\Local\Temp\kasm_startup_script.log`.

When available, Kasm Windows Autoscaling uses Cloudbase-Init to execute the configured Startup Scripts. For autoscale errors that occur prior to invoking `Init-VM-Task.ps1`, refer to the Cloudbase logs found at `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log`.



