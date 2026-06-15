#!/usr/bin/env bash
# TEMPLATE NOTE: Python str.format() template. All brace patterns are intentional, do not alter.
set -euo pipefail

# Feature flags. Override any of these from the bootstrap via the matching KASM_* env
# var (e.g. export KASM_ENABLE_AD_JOIN=1). Unset falls back to the default shown.
ENABLE_KASMVNC="${{KASM_ENABLE_KASMVNC:-0}}"
ENABLE_XRDP="${{KASM_ENABLE_XRDP:-1}}"
ENABLE_KDS="${{KASM_ENABLE_KDS:-1}}"
ENABLE_EPEL="${{KASM_ENABLE_EPEL:-1}}"
ENABLE_IPTABLES="${{KASM_ENABLE_IPTABLES:-1}}"
ENABLE_AD_JOIN="${{KASM_ENABLE_AD_JOIN:-0}}"

# Values provided by Kasm autoscale. When pasted directly, Kasm substitutes these
# placeholders into the script. When the script is hosted, bootstrap.sh exports them as
# KASM_* environment variables (those take precedence); the placeholder fallback is used
# only when the script is pasted directly.
KASM_UPSTREAM_AUTH_ADDRESS="${{KASM_UPSTREAM_AUTH_ADDRESS:-{upstream_auth_address}}}"
KASM_CHECKIN_JWT="${{KASM_CHECKIN_JWT:-{checkin_jwt}}}"
KASM_CONNECTION_USERNAME="${{KASM_CONNECTION_USERNAME:-{connection_username}}}"
KASM_CONNECTION_PASSWORD="${{KASM_CONNECTION_PASSWORD:-{connection_password}}}"

# AD join (only used when ENABLE_AD_JOIN=1)
AD_DOMAIN="${{KASM_DOMAIN:-{domain}}}"
AD_JOIN_PASSWORD="${{KASM_AD_JOIN_CREDENTIAL:-{ad_join_credential}}}"     # Kasm one-time machine-account password

# Optional: space-separated list of AD DNS servers (Domain Controller IPs) for SRV record
# resolution. Leave empty to use existing VNET/DHCP DNS configuration. Recommended for
# redundancy: "192.168.1.1 192.168.1.2" or omit to rely on preconfigured DNS.
AD_DNS_SERVER="${{KASM_AD_DNS_SERVER:-}}"   # e.g. export KASM_AD_DNS_SERVER="192.168.100.6 192.168.100.7"

# Set the machine's FQDN to <shortname>.<AD_DOMAIN> before joining. Required for the
# self-join to be allowed to write its own <AD_DOMAIN> SPNs (AD validated writes only
# permit SPNs matching dNSHostName). Without this, cloud-provider FQDNs (e.g.
# *.oraclevcn.com) cause CONSTRAINT_ATT_TYPE on servicePrincipalName during join.
SET_DOMAIN_FQDN="${{KASM_SET_DOMAIN_FQDN:-1}}"


LOG_FILE="/var/log/kasm_install.log"
mkdir -p /var/log
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
echo "===== KASM RPM INSTALL STARTED $(date) =====" >> "$LOG_FILE"
exec > >(stdbuf -oL -eL tee -a "$LOG_FILE") 2>&1

# Detect OS — used by install_epel and install_kasmvnc
. /etc/os-release
OS_ID="$ID"
OS_MAJOR=$(echo "${{VERSION_ID:-}}" | cut -d'.' -f1)
echo "[INFO] Detected OS: $OS_ID $OS_MAJOR"

# Wait for the package-manager lock (held during boot-time auto-patching) and
# retry transient download failures.
dnf() {{
  command dnf --setopt=lock_timeout=600 --setopt=retries=10 "$@"
}}

configure_iptables() {{
  echo "[INFO] Adding firewall rules at $(date)"

  if systemctl is-active --quiet firewalld; then
    # firewall-cmd hangs on D-Bus early in boot on Oracle Linux, so we avoid it and
    # let firewall-offline-cmd be the sole authority modifying the permanent config.
    # The daemon must be stopped first: this prevents runtime/permanent state from
    # diverging and avoids any requirement for a subsequent D-Bus-based reload. Enable
    # before stopping to keep the window without active rules as short as possible.
    # NOTE: if firewall behaviour regresses, revisit this stop -> offline -> start
    # sequence (and the enable-before-stop ordering) before changing anything else.
    systemctl enable firewalld || true
    systemctl stop firewalld || true

    if [ "$ENABLE_XRDP"    -eq 1 ]; then firewall-offline-cmd --add-port=3389/tcp || true; fi
    if [ "$ENABLE_KDS"     -eq 1 ]; then firewall-offline-cmd --add-port=4902/tcp || true; fi
    if [ "$ENABLE_KASMVNC" -eq 1 ]; then firewall-offline-cmd --add-port=5902/tcp || true; fi

    systemctl start firewalld || {{ echo "[ERROR] firewalld failed to start; host firewall not active" >&2; exit 1; }}
  else
    dnf install -y iptables-services
    systemctl enable iptables
    systemctl start iptables

    if [ "$ENABLE_XRDP"    -eq 1 ]; then iptables -I INPUT -p tcp --dport 3389 -j ACCEPT; fi
    if [ "$ENABLE_KDS"     -eq 1 ]; then iptables -I INPUT -p tcp --dport 4902 -j ACCEPT; fi
    if [ "$ENABLE_KASMVNC" -eq 1 ]; then iptables -I INPUT -p tcp --dport 5902 -j ACCEPT; fi

    service iptables save
  fi
}}

install_epel() {{
  echo "[INFO] Installing EPEL for $OS_ID $OS_MAJOR"
  # dnf config-manager requires dnf-plugins-core; absent on minimal installs
  dnf install -y dnf-plugins-core
  case "$OS_ID" in
    ol)
      dnf install -y oracle-epel-release-el${{OS_MAJOR}}
      dnf config-manager --enable ol${{OS_MAJOR}}_developer_EPEL
      ;;
    rhel)
      dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${{OS_MAJOR}}.noarch.rpm"
      # CodeReady Linux Builder is required for some EPEL package dependencies on RHEL.
      # The repo name differs between bare-metal RHEL, RHUI cloud images, and RHEL 9's 'crb' alias —
      # try each until one succeeds. 'powertools' is a CentOS-only fallback.
      ARCH=$(uname -m)
      dnf config-manager --enable "codeready-builder-for-rhel-${{OS_MAJOR}}-${{ARCH}}-rpms" 2>/dev/null \
        || dnf config-manager --enable "codeready-builder-for-rhel-${{OS_MAJOR}}-rhui-rpms" 2>/dev/null \
        || dnf config-manager --enable crb 2>/dev/null \
        || dnf config-manager --enable powertools 2>/dev/null \
        || echo "[WARN] Could not enable CodeReady Builder / CRB repo — some EPEL deps may not resolve" >&2
      ;;
    *)
      echo "[ERROR] EPEL install not supported for OS: $OS_ID" >&2
      return 1
      ;;
  esac
}}

install_xfce() {{
  if ! dnf group info "Xfce" &>/dev/null; then
    if [ "$ENABLE_EPEL" -eq 0 ]; then
      echo "[ERROR] Xfce group is not available in configured repos. Set ENABLE_EPEL=1 to install EPEL first." >&2
    else
      echo "[ERROR] Xfce group is not available even though EPEL was enabled. install_epel may have partially failed — check the log above for EPEL or CRB errors before retrying." >&2
    fi
    return 1
  fi
  dnf groupinstall -y "Xfce"
  dnf install -y \
    supervisor \
    xfce4-terminal \
    xterm \
    xclip \
    dbus-x11 \
    xorg-x11-xauth \
    xorg-x11-server-Xorg
}}

# Optional: screenshot tooling
install_screenshot_tools() {{
  if dnf install -y gnome-screenshot; then
    echo "[INFO] gnome-screenshot installed successfully"
  else
    echo "[WARN] gnome-screenshot not available; screenshot API may be limited on this system"
  fi
}}

install_kasmvnc() {{
  cd /tmp

  KASM_VNC_PATH=/usr/share/kasmvnc
  ARCH=$(uname -m)

  # RHEL and OL share binary-compatible RPMs; KasmVNC ships one Oracle build per major version
  case "$OS_ID-$OS_MAJOR" in
    ol-9|rhel-9)   KASMVNC_DISTRO="oracle_9" ;;
    ol-8|rhel-8)   KASMVNC_DISTRO="oracle_8" ;;
    *)
      echo "[ERROR] KasmVNC: unsupported distro $OS_ID $OS_MAJOR" >&2
      return 1
      ;;
  esac

  if [[ "$ARCH" == "x86_64" ]]; then
    BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_${{KASMVNC_DISTRO}}_1.4.0_x86_64.rpm"
  else
    BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_${{KASMVNC_DISTRO}}_1.4.0_aarch64.rpm"
  fi

  KASM_VNC_PASSWD="$KASM_CONNECTION_PASSWORD"
  KASM_VNC_USER="$KASM_CONNECTION_USERNAME"

  dnf install -y \
    gettext \
    openssl \
    libXfont2 \
    xorg-x11-fonts-Type1

  wget "$BUILD_URL" -O kasmvncserver.rpm
  dnf install -y ./kasmvncserver.rpm
  rm -f kasmvncserver.rpm

  [ ! -e $KASM_VNC_PATH/www/vnc.html ] && \
    ln -s $KASM_VNC_PATH/www/index.html $KASM_VNC_PATH/www/vnc.html

  mkdir -p $KASM_VNC_PATH/www/Downloads

  chown -R 0:0 $KASM_VNC_PATH
  chmod -R og-w $KASM_VNC_PATH
  chown -R 1000:0 $KASM_VNC_PATH/www/Downloads

  echo -e "$KASM_VNC_PASSWD\n$KASM_VNC_PASSWD\n" | \
    kasmvncpasswd -u $KASM_VNC_USER -w "/home/$KASM_VNC_USER/.kasmpasswd"

  chown -R 1000:0 "/home/$KASM_VNC_USER/.kasmpasswd"
  getent group ssl-cert >/dev/null 2>&1 && usermod -aG ssl-cert "$KASM_VNC_USER" || true

  su -l -c 'vncserver -select-de XFCE' $KASM_VNC_USER
}}

install_xrdp() {{
  # Precheck: verify xrdp is available; if not, EPEL must be enabled and working
  if ! dnf list available xrdp &>/dev/null; then
    if [ "$ENABLE_EPEL" -eq 0 ]; then
      echo "[ERROR] xrdp is not available in configured repos. Set ENABLE_EPEL=1 to install EPEL first." >&2
    else
      echo "[ERROR] xrdp is not available even though EPEL was enabled. install_epel may have partially failed — check the log above for EPEL or CRB errors before retrying." >&2
    fi
    return 1
  fi

  dnf install -y xrdp

  systemctl enable xrdp
  systemctl restart xrdp

  sleep 1

  echo "xfce4-session" > /etc/skel/.xsession
  echo "xfce4-session" > /etc/skel/.Xsession

  cat >/etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
exec dbus-launch --exit-with-session xfce4-session
EOF

  chmod +x /etc/xrdp/startwm.sh

  sleep 1

  mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml

  bash -c 'cat >/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="blank-delay" type="int" value="0"/>
  <property name="lock-delay" type="int" value="0"/>
  <property name="idle-delay" type="int" value="0"/>
</channel>
EOF'

  bash -c 'cat >/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="power-button-action" type="empty"/>
    <property name="show-tray-icon" type="bool" value="false"/>
    <property name="dpms-enabled" type="bool" value="false"/>
  </property>
</channel>
EOF'

  mkdir -p /etc/polkit-1/localauthority/50-local.d

  bash -c 'cat >/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord All Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.*
ResultActive=yes
EOF'

  sleep 1
  systemctl restart xrdp
}}

install_kds() {{

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)          KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_amd64.rpm" ;;
    aarch64|arm64)   KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_arm64.rpm" ;;
    *)               echo "[ERROR] Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac

  cd /tmp
  wget "$KDS_RPM_URL" -O kasm-desktop-service.rpm

  dnf install -y ./kasm-desktop-service.rpm
  rm -f kasm-desktop-service.rpm

  sleep 2

  KASM_HOST_NAME="$KASM_UPSTREAM_AUTH_ADDRESS"
  REG_TOKEN="$KASM_CHECKIN_JWT"
  API_HOST=$(echo "$KASM_HOST_NAME" | cut -d'/' -f1 | cut -d':' -f1)
  API_PORT=443

  # Bound the check-in so an unreachable deployment cannot hang boot indefinitely.
  timeout 300 bash /opt/kasm-desktop-service/scripts/register_wizard.sh \
    --register \
    --no-gui \
    --api-host="$API_HOST" \
    --api-port="$API_PORT" \
    --token="$REG_TOKEN" \
  || {{ echo "[ERROR] KDS registration failed or timed out against $API_HOST:$API_PORT" >&2; exit 1; }}

  sleep 2

  systemctl enable kasm-desktop.service
  systemctl restart kasm-desktop.service || systemctl start kasm-desktop.service
}}

install_ad_dependencies() {{
  echo "[INFO] Installing AD dependencies"
  dnf install -y \
    realmd sssd sssd-tools adcli \
    oddjob oddjob-mkhomedir \
    samba-common-tools \
    bind-utils \
    chrony
}}

set_domain_fqdn() {{
  # Make the host's FQDN <shortname>.<AD_DOMAIN> before joining. adcli derives
  # dNSHostName and the SPN set from the FQDN; AD's self-join "validated write"
  # only allows SPNs matching dNSHostName, so a cloud-provider FQDN (e.g.
  # *.oraclevcn.com) triggers CONSTRAINT_ATT_TYPE on servicePrincipalName and the
  # <AD_DOMAIN> SPNs/keytab entries are silently lost.
  [ "$SET_DOMAIN_FQDN" -eq 1 ] || return 0
  local short fqdn current
  short=$(hostname -s)
  fqdn="${{short,,}}.${{AD_DOMAIN}}"
  current=$(hostname -f 2>/dev/null || hostname)
  # If the FQDN is already within the AD domain (e.g. set automatically by DHCP/
  # cloud-init), leave it alone rather than rewriting and risking breakage.
  case "$current" in
    *".$AD_DOMAIN")
      echo "[INFO] FQDN already within $AD_DOMAIN ($current) — leaving as-is"
      return 0
      ;;
  esac
  echo "[INFO] Setting FQDN to $fqdn for AD join (was: $current)"
  hostnamectl set-hostname "$fqdn"
  # Map the FQDN locally so hostname -f and adcli resolve it even when the forward
  # A record has not propagated yet in AD DNS.
  if ! grep -qE "\b$fqdn\b" /etc/hosts; then
    echo "127.0.1.1 $fqdn ${{short,,}}" >>/etc/hosts
  fi
}}

configure_dns_for_ad() {{
  if [ -z "$AD_DNS_SERVER" ]; then
    echo "[INFO] AD_DNS_SERVER not set — relying on existing DNS to reach the domain"
    return
  fi
  if command -v nmcli >/dev/null 2>&1; then
    echo "[INFO] Configuring DNS for AD via nmcli: $AD_DNS_SERVER"
    local dev nic
    dev=$(ip route show default 2>/dev/null | awk 'NR==1 {{print $5}}')
    if [ -z "$dev" ]; then
      echo "[ERROR] Could not determine default route interface" >&2
      exit 1
    fi
    nic=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v d="$dev" '$2 == d {{print $1}}' | head -1)
    if [ -z "$nic" ]; then
      echo "[ERROR] No active NetworkManager connection found for device $dev" >&2
      exit 1
    fi
    echo "[INFO] Updating connection: $nic (device: $dev)"
    nmcli connection modify "$nic" ipv4.dns "$AD_DNS_SERVER" ipv4.ignore-auto-dns yes
    nmcli connection reload
    nmcli connection up "$nic" || echo "[WARN] nmcli connection up failed — DNS change may not be active until next reconnect" >&2
  else
    echo "[INFO] nmcli not available — configuring DNS via /etc/resolv.conf"
    local tmp target
    tmp=$(mktemp)
    for server in $AD_DNS_SERVER; do
      printf 'nameserver %s\n' "$server" >>"$tmp"
    done
    grep -v "^nameserver" /etc/resolv.conf >>"$tmp" || true
    if [ -L /etc/resolv.conf ]; then
      target=$(readlink -f /etc/resolv.conf)
      echo "[INFO] /etc/resolv.conf is a symlink -> $target; writing to target to preserve link"
      cp "$tmp" "$target"
      rm -f "$tmp"
    else
      mv "$tmp" /etc/resolv.conf
    fi
  fi
}}

configure_krb5_realm() {{
  # Write a minimal krb5 default_realm ONLY when none is configured anywhere — active in
  # /etc/krb5.conf or any conf.d snippet. RHEL/OL ship it commented out, and adcli can
  # fail with "Configuration file does not specify default realm" when the realm cannot
  # be resolved from the system config. This is idempotent insurance: if the system (or a
  # previous run, an image bake, or krb5-user on Debian) already set a realm, it is left
  # untouched so a working configuration is never clobbered.
  local existing
  existing=$(grep -hE '^[[:space:]]*default_realm[[:space:]]*=' /etc/krb5.conf /etc/krb5.conf.d/*.conf 2>/dev/null | head -1 || true)
  if [ -n "$existing" ]; then
    echo "[INFO] krb5 default_realm already configured ($existing) — leaving as-is"
    return 0
  fi
  local realm
  realm=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
  echo "[INFO] No krb5 default_realm found — writing: $realm"
  mkdir -p /etc/krb5.conf.d
  printf '[libdefaults]\n    default_realm = %s\n[domain_realm]\n    .%s = %s\n    %s = %s\n' \
    "$realm" "$AD_DOMAIN" "$realm" "$AD_DOMAIN" "$realm" >/etc/krb5.conf.d/kasm-ad.conf
}}

sync_time() {{
  echo "[INFO] Syncing system clock (Kerberos requires <5 min skew)"
  systemctl enable --now chronyd
  # Wait up to ~30s for chrony to contact a source before stepping. Without this,
  # makestep can fire before any NTP sample is in and realm join later fails with
  # an opaque Kerberos clock-skew error.
  chronyc waitsync 6 0 0 5 || echo "[WARN] chrony did not reach a source within 30s" >&2
  if ! chronyc makestep; then
    echo "[WARN] chronyc makestep failed — verify NTP port 123/UDP is reachable and clock skew is under 5 minutes before realm join" >&2
  fi
}}

test_domain_resolution() {{
  echo "[INFO] Testing DNS resolution for $AD_DOMAIN"
  # Pin dig to AD_DNS_SERVER when provided so the test bypasses any stale system
  # resolver state from before configure_dns_for_ad ran. Use only the first server.
  local dig_server=""
  if [ -n "$AD_DNS_SERVER" ]; then
    dig_server="@${{AD_DNS_SERVER%% *}}"
  fi
  local srv_query="_ldap._tcp.$AD_DOMAIN"
  if ! dig +short +time=5 +tries=2 $dig_server "$srv_query" SRV | grep -q '.'; then
    echo "[ERROR] LDAP SRV records not found for $AD_DOMAIN via ${{AD_DNS_SERVER:-system resolver}}" >&2
    echo "[ERROR] timed out => 53 blocked/unreachable; SERVFAIL/REFUSED => wrong server/zone; NXDOMAIN => records missing" >&2
    dig +time=5 +tries=2 $dig_server "$srv_query" SRV 2>&1 | sed 's/^/[dig] /' >&2
    exit 1
  fi
  realm discover "$AD_DOMAIN" >/dev/null || {{
    echo "[ERROR] realm discovery failed for $AD_DOMAIN" >&2
    exit 1
  }}
  echo "[INFO] Domain resolution successful"
}}

join_domain() {{
  echo "[INFO] Joining domain $AD_DOMAIN via one-time password"
  realm join --verbose --one-time-password="$AD_JOIN_PASSWORD" "$AD_DOMAIN" || {{
    echo "[ERROR] Domain join failed" >&2
    exit 1
  }}
  echo "[INFO] Domain join successful"
}}

enable_homedir_creation() {{
  echo "[INFO] Configuring sssd and home directory creation"
  if [ ! -f /etc/sssd/sssd.conf ]; then
    echo "[ERROR] /etc/sssd/sssd.conf not found — realm join may not have completed successfully" >&2
    exit 1
  fi
  if ! grep -q "ad_gpo_map_remote_interactive" /etc/sssd/sssd.conf; then
    sed -i '/^\[domain\//a ad_gpo_map_remote_interactive = +xrdp-sesman' /etc/sssd/sssd.conf
  fi
  chown root:root /etc/sssd/sssd.conf
  chmod 600 /etc/sssd/sssd.conf
  authselect select sssd with-mkhomedir --force || true
  systemctl enable --now oddjobd
  systemctl enable sssd
  systemctl restart sssd
}}

kasm_checkin() {{
  echo "[INFO] Signaling Kasm server ready"
  if curl -k -fsS -X POST \
      -H "Content-Type: application/json" \
      --data '{{"status":"running","status_message":"Startup complete","status_progress":"100"}}' \
      "https://$KASM_UPSTREAM_AUTH_ADDRESS/api/set_server_status?token=$KASM_CHECKIN_JWT"; then
    echo "[INFO] Kasm check-in successful"
  else
    echo "[ERROR] Kasm check-in failed — server may not be marked ready in Kasm UI" >&2
  fi
}}

install_ad_join() {{
  if [ -z "$AD_DNS_SERVER" ]; then
    echo "[INFO] AD_DNS_SERVER not set — relying on preconfigured DNS (VNET/DHCP) to resolve $AD_DOMAIN" >&2
  fi
  if realm list 2>/dev/null | grep -Fiq "domain-name: $AD_DOMAIN"; then
    echo "[INFO] Already joined to $AD_DOMAIN, skipping"
    return
  fi
  install_ad_dependencies
  set_domain_fqdn
  configure_dns_for_ad
  configure_krb5_realm
  sync_time
  test_domain_resolution
  join_domain
  enable_homedir_creation
  echo "[INFO] AD join complete"
}}

sleep 5

dnf install -y wget curl || exit 1

# iptables-services is in base/appstream repos, so firewall setup runs before EPEL is configured
if [ "$ENABLE_IPTABLES" -eq 1 ]; then
  configure_iptables
fi

if [ "$ENABLE_EPEL" -eq 1 ]; then
  install_epel
fi

install_xfce
install_screenshot_tools || true

if [ "$ENABLE_KASMVNC" -eq 1 ]; then
  install_kasmvnc
fi

if [ "$ENABLE_XRDP" -eq 1 ]; then
  install_xrdp
fi

if [ "$ENABLE_AD_JOIN" -eq 1 ]; then
  install_ad_join
fi

if [ "$ENABLE_KDS" -eq 1 ]; then
  install_kds
fi

# When KDS is not installed, signal Kasm directly that the server is ready.
# KDS handles its own checkin via register_wizard.sh when ENABLE_KDS=1.
if [ "$ENABLE_KDS" -eq 0 ]; then
  kasm_checkin
fi

echo "===== KASM RPM INSTALL COMPLETED $(date) ====="
