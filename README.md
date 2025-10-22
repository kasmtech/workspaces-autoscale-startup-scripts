# Kasm AutoScale Startup Scripts
These scripts are example startup scripts that may be used for autoscaling [Servers](https://docs.kasm.com/docs/guide/compute/pools.html#autoscale-config-server-pool) and [Docker Agents](https://docs.kasm.com/docs/guide/compute/pools.html#autoscale-config-docker-agent-pool) in a Kasm Workspaces deployment.

> [!NOTE]  
> For versions compatible with older releases of Kasm Workspaces, please check the corresponding [release branches](https://github.com/kasmtech/workspaces-autoscale-startup-scripts/branches/all?query=release).

## Servers
Kasm Workspaces can auto-scale full stack VMs and add them to a [Server Pool](https://docs.kasm.com/docs/guide/compute/pools.html#autoscale-config-server-pool). You may want to add startup scripts to the VM to take actions on boot. For example, for a Windows server you may need to join it to Active Directory. For a Linux Server you may need to install and configure KasmVNC.

- [Windows VM Startup Scripts](./windows_vms)
- [Linux VM Startup Scripts](./linux_vms)

## Docker Agents
Kasm Workspaces can auto-scale [Docker Agents](https://docs.kasm.com/docs/guide/compute/pools.html#autoscale-config-docker-agent-pool) and join them to the cluster in order to fulfill client sessions of containerized desktops and applications. The VMs you spin up can be base Ubuntu images that are maintained by the Cloud Service Provider and the startup scripts can install Docker and the Kasm agent. This project provides example startup scripts you can use your auto scaled deployments. We attempt to have a single script that will work on any of the supported cloud providers.

- [Docker Agent Startup Scripts](./docker_agents)



