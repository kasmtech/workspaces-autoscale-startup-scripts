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
| upstream_auth_address      | The resolvable hostname, IP, or FQDN of the KASM API server. The token `{upstream_auth_address}` will be replaced with the value of "Zone" > "Upstream Auth Address" from the autoscale configuration's zone. |
| checkin_jwt        | The registration token (JWT) created by Kasm for the newly created server. The token `{checkin_jwt}` will be replaced with a Kasm-generated registration token that is valid for 4 hours. |                                                                                                                                                                

### Escaping Brackets
If your script uses curly brackets, aside from Kasm variables, you must escape them by doubling them up. Here is an example.

```bash
VARIABLE="This is an example of curly brackets being escaped in a script."
echo "${{VARIABLE}}"
```

## Example
The example script [ubuntu.sh](./ubuntu.sh) installs Xrdp, Kasm Desktop Service -Linux, KasmVNC on the Ubuntu VM and configures a KasmVNC user using the configured username and password in the [auto-scale configuration's](https://docs.kasm.com/docs/develop/how-to/autoscale/infrastructure_components/autoscale_config_server) Connection User and Connection Password fields. Kasm Workspaces can also work with a traditional VNC server. The example ubuntu.sh script also includes a function for installing, configuring, and starting tigervnc on the default port 5901.

When using this autoscale configuration:
- XRDP requires TCP port 3389 to be open for remote desktop connections.
- The Kasm Desktop Service (Linux edition) requires TCP port 4902 to be open so that the service can communicate with the Kasm API and complete registration and keepalive checks.
- If your environment enforces host-level firewalls (such as iptables), ensure these ports are permitted. The example script includes iptables configuration to automatically allow required ports.
- Logs for the autoscale setup process are available at `/var/log/kasm_install.log`.

Additional KasmVNC installers for other distros can be found on the public [KasmVNC github repository](https://github.com/kasmtech/KasmVNC/releases)