# Kasm AutoScale Startup Scripts
These scripts are example startup scripts that may be used for autoscaling [Servers](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-config-server-pool) and [Docker Agents](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-config-docker-agent-pool) in a Kasm Workspaces deployment.

## Servers
Kasm Workspaces can auto-scale full stack VMs and add them to a [Server Pool](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-config-server-pool). You may want to add startup scripts to the VM to take actions on boot. For example, for a Windows server you may need to join it to Active Directory. For a Linux Server you may need to install and configure KasmVNC.

## Docker Agents
Kasm Workspaces can auto-scale [Docker Agents](https://www.kasmweb.com/docs/latest/guide/compute/pools.html#autoscale-config-docker-agent-pool) and join them to the cluster in order to fulfill client sessions of containerized desktops and applications. The VMs you spin up can be base Ubuntu images that are maintained by the Cloud Service Provider and the startup scripts can install Docker and the Kasm agent. This project provides example startup scripts you can use your auto scaled deployments. We attempt to have a single script that will work on any of the supported cloud providers.

# Releases
Use the folder below that matches the version of Kasm Workspaces you have deployed.

## Latest
The latest folder is designed to work with all releases above the latest versioned releases listed below. At the time of this writing that would mean developer preview and beyond. Kasm Workspaces developer preview and greater support scaling general VMs which can be used as Kasm Docker Agents used to support containerized desktops and applications for end-user sessions and Windows and Linux VMs for traditional desktop sessions. 

- [Docker Agents](./latest/docker_agents/README.md)
- [Windows VMs](./latest/windows_vms/README.md)
- [Linux VMs](./latest/linux_vms/README.md)


## 1.15.0
Kasm Workspaces 1.15.0 and greater support scaling general VMs which can be used as Kasm Docker Agents used to support containerized desktops and applications for end-user sessions and Windows and Linux VMs for traditional desktop sessions. 

- [Docker Agents](./1.15.0/docker_agents/README.md)
- [Windows VMs](./1.15.0/windows_vms/README.md)
- [Linux VMs](./1.15.0/linux_vms/README.md)

## 1.14.0
Kasm Workspaces 1.14.0 and greater support scaling general VMs which can be used as Kasm Docker Agents used to support containerized desktops and applications for end-user sessions and Windows and Linux VMs for traditional desktop sessions. 

- [Docker Agents](./1.14.0/docker_agents/README.md)
- [Windows VMs](./1.14.0/windows_vms/README.md)
- [Linux VMs](./1.14.0/linux_vms/README.md)

## 1.13.0
Kasm Workspaces 1.13.0 and greater support scaling general VMs which can be used as Kasm Docker Agents used to support containerized desktops and applications for end-user sessions and Windows and Linux VMs for traditional desktop sessions. 

- [Docker Agents](./1.13.0/docker_agents/README.md)
- [Windows VMs](./1.13.0/windows_vms/README.md)
- [Linux VMs](./1.13.0/linux_vms/README.md)

## 1.12.0
Kasm Workspaces 1.12.0 and greater support scaling general VMs which can be used as Kasm Docker Agents used to support containerized desktops and applications for end-user sessions and Windows and Linux VMs for traditional desktop sessions. 

- [Docker Agents](./1.12.0/docker_agents/README.md)
- [Windows VMs](./1.12.0/windows_vms/README.md)
- [Linux VMs](./1.12.0/linux_vms/README.md)

## 1.11.0
Kasm Workspaces 1.11.0 supports scaling of Kasm Agents, which support containerized desktops and applications for end-user sessions.

- [Kasm Agents](1.11.0/README.md)

## 1.10.0
Kasm Workspaces 1.10.0 supports scaling of Kasm Agents, which support containerized desktops and applications for end-user sessions.

- [Kasm Agents](1.10.0/README.md)
