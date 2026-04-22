# VM Startup Script
In Kasm Workspaces 1.18.1 the [VM Provider](https://docs.kasm.com/docs/develop/guide/compute/vm_providers) configuration is defined in a Server Pool's [Auto Scaling](https://docs.kasm.com/docs/develop/how-to/autoscale/infrastructure_components/autoscale_config_server) configuration. Each VM provider corresponds to a cloud service provider or hypervisor. The VM Provider configuration has a place to define a startup script, which will be executed when the VM boots up. 

## Variables

Kasm replaces variables in the script that are wrapped in curly brackets, such as **{connection_username}**, with values. The following table lists the variables and a description.

| Variable Name       | Description                                                                                                                                                                                                                                                                                                          |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| connection_username | If the auto-scale configuration is set to use a static username for Kasm user sessions, the username will be contained in this variable.                                                                                                                                                                             |
| connection_password | If the auto-scale configuration is set to use a static password for Kasm user sessions, this variable will contain the password.                                                                                                                                                                                     |
| ad_join_credential  | If the auto-scale configuration is set to join the VM to an Active Directory domain, Kasm creates the AD record and sets a random password that can only be used for joining the VM to the domain. This can then be used in a Powershell startup script to complete the process of joining the system to the domain. |
| domain              | If the auto-scale configuration is set to join the VM to an Active Directory domain, this variable will contain the name of the domain.                                                                                                                                                                              |
| upstream_auth_address      | The resolvable hostname, IP, or FQDN of the KASM API server. The token `{upstream_auth_address}` will be replaced with the value of "Zone" > "Upstream Auth Address" from the autoscale configuration's zone. |
| checkin_jwt        | The registration token (JWT) created by Kasm for the newly created server. The token `{checkin_jwt}` will be replaced with a Kasm-generated registration token that is valid for 4 hours. |                                                                                                                                                                

### Escaping Brackets
If your script uses curly brackets, aside from Kasm variables, you must escape them by doubling them up. Here is an example.

```bash
VARIABLE="This is an example of curly brackets being escaped in a script."
echo "${{VARIABLE}}"
```

## Examples

### Ubuntu — [ubuntu.sh](./ubuntu.sh)

Installs Xfce, Xrdp, Kasm Desktop Service, and KasmVNC on an Ubuntu VM. Configure which components are installed by setting the flags at the top of the script:

| Flag | Default | Description |
|------|---------|-------------|
| `ENABLE_KASMVNC` | `1` | Install and configure KasmVNC |
| `ENABLE_XRDP` | `1` | Install and configure xrdp for RDP access |
| `ENABLE_KDS` | `1` | Install and register Kasm Desktop Service |
| `ENABLE_IPTABLES` | `0` | Open required firewall ports via UFW (preferred) or iptables |

### Oracle Linux 9 — [oracle_9.sh](./oracle_9.sh)

Installs Xfce, Xrdp, Kasm Desktop Service, and optionally KasmVNC on an Oracle Linux 9 VM. Configure which components are installed by setting the flags at the top of the script:

| Flag | Default | Description |
|------|---------|-------------|
| `ENABLE_KASMVNC` | `0` | Install and configure KasmVNC |
| `ENABLE_XRDP` | `1` | Install and configure xrdp for RDP access |
| `ENABLE_KDS` | `1` | Install and register Kasm Desktop Service |
| `ENABLE_EPEL` | `0` | Enable the EPEL repository before installing packages. Required if xrdp or other packages are not available in the default Oracle Linux repos. |
| `ENABLE_IPTABLES` | `0` | Open required firewall ports via firewalld (preferred) or iptables |

#### EPEL on Oracle Linux 9
Xfce and xrdp are not included in Oracle Linux 9's default repositories. Set `ENABLE_EPEL=1` to automatically enable the `ol9_developer_EPEL` repository before package installation. EPEL is disabled by default as a security precaution — verify your organization's policy before enabling it.

## Port Requirements

When using these autoscale configurations:
- XRDP requires TCP port **3389** to be open for remote desktop connections.
- The Kasm Desktop Service requires TCP port **4902** to be open so the service can communicate with the Kasm API for registration and keepalive checks.
- KasmVNC requires TCP port **5902** to be open for browser-based VNC connections.

Set `ENABLE_IPTABLES=1` to have the script open only the ports corresponding to the enabled services. On Ubuntu, UFW is used if active, falling back to raw iptables. On Oracle Linux 9, firewalld is used if active, falling back to iptables-services.

If you manage firewall rules outside the script, leave `ENABLE_IPTABLES=0` (the default).

## Logging

All installation output is captured at `/var/log/kasm_install.log`. The log file is created with mode `0600` before any output is written, so credentials substituted into the script by Kasm are not world-readable.

Additional KasmVNC installers for other distros can be found on the public [KasmVNC github repository](https://github.com/kasmtech/KasmVNC/releases)
