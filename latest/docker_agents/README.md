# Docker Agent Startup Script
In Kasm Workspaces 1.15.0 the [VM Provider](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#vm-provider-configs) configuration is defined in a Server Pool's [Auto Scaling](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-configurations) configuration. Each VM provider corresponds to a cloud service provider or hypervisor. The VM Provider configuration has a place to define a startup script, which will be executed when the VM boots up.

## Edits Required
The following subsections cover what edits to the script are required for each deployment and zone.

### Swap Size
The default swap size defined in the script on line 13 is 2GB, adjust as needed. The larger the agent, the more swap space you may wish to configure.

### Agents IP/Hostname
Lines 39 through 72 use different methods of getting either the VMs public or private IP address. Uncomment the method you wish to use. By default, it assumes AWS and that you want the private IP address. The managers in the zone must be able to communicate with the agent using this IP address. If you have the auto scale settings configured to create public DNS records, the public DNS name will be used as configured on line 80.

VMware vSphere autoscalling requires filling in the network adapter name on line 72 that the template will use in order to ensure capturing the proper IP.

## Variables

Kasm replaces variables in the script that are wrapped in curly brackets, such as **{server_hostname}**, with values. The following table lists the variables and a description.

| Variable Name         | Description                                                                                                                              |
|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| server_hostname       | If the auto-scale configuration is set to create public DNS records, this variable will contain the Kasm generated hostname for this VM. |
| server_external_fqdn  | If the auto-scale configuration is set to create public DNS records, this variable will contain the Kasm generated FQDN of this VM.      |
| manager_token         | The manager token, which will be used during the installation of the Kasm agent to register with a manager in the Zone.                  |
| upstream_auth_address | The upstream auth setting defined for the Zone. See the section below dedicated to this setting.                                         |
| server_id             | The unique ID created by Kasm for this server, which is needed for the installation of the Kasm Agent.                                   |
| provider_name         | The name of the cloud service provider the VM is deployed to, this is used by the installer of the Kasm Agent.                           |
| nginx_cert_in         | Public SSL cert used for the NGINX server on the Kasm Agent.                                                                             |
| nginx_key_in          | Private SSL key used for the NGINX Server on the Kasm Agent.                                                                             |

### Escaping Brackets
If your script uses curly brackets, aside from Kasm variables, you must escape them by doubling them up. Here is an example.

```bash
VARIABLE="This is an example of curly brackets being escaped in a script."
echo "${{VARIABLE}}"
```

In the above example, we used curly brackets around the use of the variable, as this is valid bash syntax. You must double each use of the opening and closing curly brackets.

### Upstream Auth Address
The [Upstream Auth Address](https://www.kasmweb.com/docs/latest/guide/zones/deployment_zones.html#configuring-deployment-zones) is a Zone setting that by default is `$request_host$`, which is a magic variable that gets replaced with the hostname of the request made by the user. When an agent gets a request for a specific container's KasmVNC session, it needs to authenticate the request. If the respective Zone's **Upstream Auth Address** is set to `$request_host$`, the auth request is sent to that host. This works in most basic scenarios, but in complex deployments may not be what is desired.

The [ubuntu.sh](./ubuntu.sh) script assumes that you have configured the **Upstream Auth Address** zone setting to an actual IP address or hostname. Therefore, you either need to configure the **Upstream Auth Address** in the Zone settings or you need to remove the `{upstream_auth_address}` in the ubuntu.sh script and replace it with an IP address or hostname of one of the managers in the zone. The manager, is one of the services running on the webapp role server. If you have multiple in the Zone, you could create DNS A records to point to all of them or you could use a load balancer.

### NGINX SSL Certs
If you are using a direct to agent flow, where the iframe for the desktop connection goes directly to the agent, a wild card cert is needed for the domain. Each agent will have a hostname under that sub domain. For example, if your users access Kasm at `app.kasm.example.com`, your agents may have hostnames of `<autogenerated>.kasm.example.com` where <autogenerated> is replaced by a host name generated by Kasm. You would need a wild card cert for *.kasm.exmaple.com and that would go into the Zone settings, so it could be used by the startup script.

If you are not using a direct to agent flow, that means all requests go through the front door and are proxied to the appropriate agent. This is the default workflow and it works well for most scenarios. In this workflow you don't necessarily need to specify the SSL cert and key, as the default install of the Kasm Agent will use self signed certs. Your organization, however, may require that services use a cert signed by your CA. If self-signed certs are acceptable, you can merely use a space in the auto scale settings for the public ssl cert and private key fields. Then modify the ubuntu.sh script by commenting out lines 84 and 85.

### KubeVirt
If you are installing agents in KubeVirt uncomment lines 96-98 to add the qemu agent install in [ubuntu.sh](./ubuntu.sh).

### cloud-config.yaml
This is a default cloud init configuation that can be used as a startup script for Harvester/KubeVirt agents.