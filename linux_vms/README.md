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

**NOTE: Linux AD join uses one-time password, not username**
On Linux, Kasm pre-creates the machine account in AD and provides a one-time join password via `{ad_join_credential}`. The scripts use `realm join --one-time-password` with this value. No AD username is required.

### Escaping Brackets
If your script uses curly brackets, aside from Kasm variables, you must escape them by doubling them up. Here is an example.

```bash
VARIABLE="This is an example of curly brackets being escaped in a script."
echo "${{VARIABLE}}"
```

## Examples

### Debian / Ubuntu — [deb.sh](./deb.sh)

Installs Xfce, Xrdp, Kasm Desktop Service, and KasmVNC. The script detects the distro at runtime from `/etc/os-release` and selects the correct KasmVNC package automatically.

**Supported distros:**

| Distro | Version |
|--------|---------|
| Ubuntu | 22.04 (Jammy), 24.04 (Noble) |
| Debian | 11 (Bullseye), 12 (Bookworm) |

**Configuration flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `ENABLE_KASMVNC` | `0` | Install and configure KasmVNC |
| `ENABLE_XRDP` | `1` | Install and configure xrdp for RDP access |
| `ENABLE_KDS` | `1` | Install and register Kasm Desktop Service |
| `ENABLE_IPTABLES` | `1` | Open required firewall ports via UFW (preferred on Ubuntu) or iptables |
| `ENABLE_AD_JOIN` | `0` | Join the VM to an Active Directory domain |

**AD join variables (when `ENABLE_AD_JOIN=1`):**

| Variable | Source | Description |
|----------|--------|-------------|
| `AD_DOMAIN` | Kasm `{domain}` | The AD domain to join (e.g. `corp.example.com`) |
| `AD_JOIN_PASSWORD` | Kasm `{ad_join_credential}` | One-time machine account password created by Kasm |
| `AD_DNS_SERVER` | **Optional** | Space-separated list of Domain Controller / AD DNS server IPs for redundancy (e.g. `192.168.1.10` or `192.168.1.10 192.168.1.11`). Leave empty to use preconfigured VNET/DHCP DNS. Set this when DHCP DNS does not resolve AD SRV records. |

### Oracle Linux / RHEL — [rpm.sh](./rpm.sh)

Installs Xfce, Xrdp, Kasm Desktop Service, and optionally KasmVNC. The script detects the distro at runtime from `/etc/os-release` and selects the correct KasmVNC package and EPEL installation method automatically.

**Supported distros:**

| Distro | Version |
|--------|---------|
| Oracle Linux | 8, 9 |
| RHEL | 8, 9 |

**Configuration flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `ENABLE_KASMVNC` | `0` | Install and configure KasmVNC |
| `ENABLE_XRDP` | `1` | Install and configure xrdp for RDP access |
| `ENABLE_KDS` | `1` | Install and register Kasm Desktop Service |
| `ENABLE_EPEL` | `1` | Enable the EPEL repository before installing packages. Required for Xfce and xrdp on Oracle Linux and RHEL. |
| `ENABLE_IPTABLES` | `1` | Open required firewall ports via firewalld (preferred) or iptables |
| `ENABLE_AD_JOIN` | `0` | Join the VM to an Active Directory domain |

**AD join variables (when `ENABLE_AD_JOIN=1`):** same as `deb.sh` above. `AD_DNS_SERVER` is optional — set it to a space-separated list of DC IPs if DHCP DNS doesn't resolve AD SRV records (e.g. `192.168.1.10 192.168.1.11` for redundancy).

> **DNS configuration note:** if `NetworkManager` (`nmcli`) is present, DNS is configured via the active connection profile so it survives reconnects. On minimal installs without NetworkManager, the script falls back to writing `/etc/resolv.conf` directly. Multiple DNS servers are supported (space-separated in `AD_DNS_SERVER`) for redundancy; all are configured automatically.

#### EPEL on Oracle Linux and RHEL
Xfce and xrdp are not included in the default repositories for Oracle Linux or RHEL. `ENABLE_EPEL=1` is the default so the script works out of the box. The EPEL setup is distro-aware:

- **Oracle Linux:** installs `oracle-epel-release-el{8,9}` and enables `ol{8,9}_developer_EPEL`
- **RHEL:** installs EPEL from `dl.fedoraproject.org` and enables CodeReady Linux Builder (CRB / powertools), which is required for some EPEL package dependencies

If your organization's security policy prohibits third-party repositories, set `ENABLE_EPEL=0` and ensure the required packages are available through an internal mirror.

## AWS EC2 — user data size limit

AWS EC2 enforces a **hard 16,384-byte (16 KiB) limit on instance user data** — it is not
an adjustable quota. The scripts above exceed (or sit right at) that limit once Kasm
substitutes the template variables, so they cannot be pasted directly into an EC2
autoscale user-data field. Stripped-down copies that fit are in
[`aws_scripts/`](./aws_scripts/) — see that folder's [README](./aws_scripts/README.md)
for details and the more robust alternatives (gzip / host + download). Every other
provider Kasm autoscale supports (Azure, GCP, OCI, DigitalOcean) has a much larger limit
and should keep using the canonical scripts above.

## AD Domain Join — Autoscale Configuration Notes

When using AD join with autoscale:

- Enable **Add Active Directory Computer Record** in the autoscale config and select the LDAP config for the domain.
- Set **Connection Credential Type** to **SSO User Accounts** and **SSO Domain** to your AD domain.
- Enable **Require Server Checkin** so Kasm waits for the VM to fully configure itself before accepting sessions.
- The **Kasm Desktop Service Installed** toggle must match whether KDS is actually running on the VM:
  - `ENABLE_KDS=1` → toggle **on**: KDS registers the server and handles checkin automatically via `register_wizard.sh`.
  - `ENABLE_KDS=0` → toggle **off**: the script signals readiness via `POST /api/set_server_status` using `{checkin_jwt}` at the end of the startup script.
- Both configurations work with AD SSO RDP. With `ENABLE_KDS=1`, KDS also provides keepalive heartbeats to Kasm; with `ENABLE_KDS=0`, the script performs a direct HTTPS check-in to `{upstream_auth_address}` — outbound port **443** to the Kasm API must be reachable in addition to inbound **3389** for RDP.

### Failure behavior

The script runs under `set -euo pipefail`, so any failure in the AD join sequence (DNS resolution, time sync, realm discovery, realm join, or sssd configuration) aborts the entire startup script. Consequences:

- `install_kds` will **not** run, so the server will never register with the Kasm API.
- The fallback `kasm_checkin` (only used when `ENABLE_KDS=0`) will also not run.
- The VM will appear stuck in the autoscale UI until the **Require Server Checkin** timeout expires.

When troubleshooting a server that never came up, check `/var/log/kasm_install.log` on the VM — the AD failure will be near the bottom of the log.

### Ports to expose on the AD server

The Kasm VMs need **outbound** access to the following ports on the Domain Controllers. Open these on the AD-side firewall (and any network ACL between the Kasm VM subnet and the DC subnet):

| Port           | Protocol  | Purpose                                                         |
|----------------|-----------|-----------------------------------------------------------------|
| 53             | TCP + UDP | DNS (SRV record lookups for `_ldap._tcp.<domain>`, etc.)        |
| 88             | TCP + UDP | Kerberos authentication                                         |
| 123            | UDP       | NTP — required for time sync before realm join (`<5 min` skew)  |
| 389            | TCP       | LDAP — realm join uses plain LDAP, not LDAPS (636)              |
| 445            | TCP       | SMB — machine account creation and SPN registration             |
| 464            | TCP + UDP | Kerberos password set / change (kpasswd)                        |
| 3268           | TCP       | Global Catalog (multi-domain forests / cross-domain lookups)    |
| 49152 – 65535  | TCP       | RPC dynamic port range — used by `adcli` for several join steps |

Notes:
- The RPC dynamic range is wide by default on Windows Server 2008+. If your firewall policy can't open the full range, you can restrict the DC's RPC range via the registry (`Internet Communication Management` → `RPC` → `Internet`); narrow it to a few hundred ports and open just that band.
- NTP (123/UDP) can point at your own time source instead of the DC if you have one — the script syncs against whatever chrony's configured pool is, then `realm join` only cares that the resulting clock skew is < 5 minutes.

### Security note — one-time password visibility

The Kasm-supplied OTP is passed to `realm join` as a command-line argument (`--one-time-password=…`), which means it is briefly visible in `/proc/<pid>/cmdline` (i.e. via `ps`) for the duration of the join. Since this is a single-use credential, it executes on a fresh VM with no other interactive users, and the join completes in seconds, the practical exposure is minimal. If your threat model requires hiding it entirely, the script would need to be rewritten to call `adcli` with `--stdin-password` and configure sssd manually (bypassing `realmd`).

## Port Requirements

When using these autoscale configurations:
- XRDP requires TCP port **3389** to be open for remote desktop connections.
- The Kasm Desktop Service requires TCP port **4902** to be open so the service can communicate with the Kasm API for registration and keepalive checks.
- KasmVNC requires TCP port **5902** to be open for browser-based VNC connections.

By default (`ENABLE_IPTABLES=1`), the script opens only the ports corresponding to the enabled services. On Debian/Ubuntu, UFW is used if active, falling back to raw iptables. On Oracle Linux/RHEL, firewalld is used if active, falling back to iptables-services.

If you manage firewall rules outside the script, set `ENABLE_IPTABLES=0`.

## Logging

All installation output is captured at `/var/log/kasm_install.log`. The log file is created with mode `0600` before any output is written, so credentials substituted into the script by Kasm are not world-readable.

Additional KasmVNC installers for other distros can be found on the public [KasmVNC github repository](https://github.com/kasmtech/KasmVNC/releases)
