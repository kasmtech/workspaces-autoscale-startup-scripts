# VM Startup Script
In Kasm Workspaces 1.13.0 the [VM Provider](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#vm-provider-configs) configuration is defined in a Server Pool's [Auto Scaling](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-configurations) configuration. Each VM provider corresponds to a cloud service provider or hypervisor. The VM Provider configuration has a place to define a startup script, which will be executed when the VM boots up. 

## Variables

Kasm replaces variables in the script that are wrapped in curly brackets, such as **{connection_username}**, with values. The following table lists the variables and a description.

| Variable Name      | Description                              |
| ------------------ | ---------------------------------------- |
| connection_username | If the auto-scale configuration is set to use a static username for Kasm user sessions, the username will be contained in this variable. |
| connection_password | If the auto-scale configuration is set to use a static password for Kasm user sessions, this variable will contain the password. |
| ad_join_credential | If the auto-scale configuration is set to join the VM to an Active Directory domain, Kasm creates the AD record and sets a random password that can only be used for joining the VM to the domain. This can then be used in a Powershell startup script to complete the process of joining the system to the domain. |
| domain | If the auto-scale configuration is set to join the VM to an Active Directory domain, this variable will contain the name of the domain. |

### Escaping Brackets
If your script uses curly brackets, aside from Kasm variables, you must escape them by doubling them up. Here is an example.

```powershell
$joinCred = New-Object pscredential -ArgumentList ([pscustomobject]@{{ UserName = $null; Password = (ConvertTo-SecureString -String '{ad_join_credential}' -AsPlainText -Force)[0] }})
```

In this example, curly open and closing brackets that are not in reference to Kasm variables, are doubled up.

## Script Variations

There are two important factors that determine what should be in the script, and we provide a few examples in this repository. The first is the cloud service provider and the second is whether Windows local accounts will be used or Active Directory accounts.

### Cloud Service Providers

Each cloud service provider behaves a bit differently and may expect the startup script in a different format.

#### Azure

Unlike most other cloud providers, Azure does not automatically execute the custom data script on startup. You must create a custom Azure VM Image with sysprep and configure Windows such that C:\AzureData\CustomData.bin is executed at startup. There a number of different methods that could be used to do this, the following is a method that we have used and is known to work. Kasm Technologies is providing this as an open source reference. This should be adapted to meet your specific use-case and security requirements.

Start a new VM using the appropriate base image. Install the required software and configure as needed for your use-case.

Create a file at `C:\AzureData\startup.cmd` with the following content.
```
schtasks /Delete /TN "DomainJoin" /F
cd C:\AzureData
ren CustomData.bin CustomData.ps1
PowerShell -Command "Set-ExecutionPolicy Unrestricted"
PowerShell -file C:\AzureData\CustomData.ps1
```

Open a Windows Command Prompt as admin and execute the following command to create a scheduled task that will execute the above script at startup.
```
schtasks /create /tn "DomainJoin" /sc onstart /delay 0000:30 /rl highest /ru system /tr "cmd /c C:\AzureData\startup.cmd  > C:\AzureData\startup.log 2>&1"
```

Now run sysprep on the VM and shut it down, use the Azure portal to create a new VM Image using Azure's [documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/generalize#windows).

Now update your Kasm deployment's VM Provider configuration in your Server Pool, to point to the newly created image. When a VM created by Kasm is created, it will execute the startup script on boot. The startup script will remove the scheduled task, execute the PowerShell script injected by Kasm, and then delete that powershell script. 

The example [azure_join_ad.txt](./azure_join_ad.txt) joins the system to the domain and reboots it. This assumes that the [auto-scale configuration](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-configurations) is set to auto join VMs to the domain and that LDAP SSO is configured.

See our Windows Server video, which walks through auto AD joining and LDAP SSO.
<iframe src='https://www.youtube.com/embed/_WCee4-E4vA' frameborder='0' allowfullscreen></iframe>


#### AWS 
AWS needs to have the PowerShell script defined in XML. See our example [aws_local_accounts.txt](./aws_local_account.txt) which creates a local Windows account using the username and password that are configured in the [auto-scale configuration](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-configurations) connection settings. 

#### OCI
See our example [oci_local_accounts.txt](./oci_local_account.txt) which creates a local Windows account using the username and password that are configured in the [auto-scale configuration](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-configurations) connection settings. 

### Windows Service
The [Kasm Windows service](https://www.kasmweb.com/docs/latest/guide/windows/windows_service.html) provides many features and is highly recommended to install. One of the feature is provides is automatic Kasm managed local Windows accounts. With the Windows service installed, the above two script examples that create a local Windows account are unnecessary. Instead, the Kasm service will automatically create local Windows accounts, unique to each Kasm user, one a new session is created. A randomized password is used for each session. The username in Windows of a user contains portions of the Kasm username and user ID. See the [aws_install_windows_service.txt](./aws_install_windows_service.txt) and [oci_install_widows_service.txxt](./oci_install_windows_service.txt) for an examples of how to install the agent automatically and have it register with your deployment on boot of the VM. 