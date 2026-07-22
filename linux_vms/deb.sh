#!/usr/bin/env bash
# TEMPLATE NOTE: Python str.format() template. All brace patterns are intentional, do not alter.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Feature flags. Override any of these from the bootstrap via the matching KASM_* env
# var (e.g. export KASM_ENABLE_AD_JOIN=1). Unset falls back to the default shown.
ENABLE_KASMVNC="${{KASM_ENABLE_KASMVNC:-0}}"
ENABLE_XRDP="${{KASM_ENABLE_XRDP:-1}}"
ENABLE_KDS="${{KASM_ENABLE_KDS:-1}}"
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

# Flags must be 0 or 1 — anything else (e.g. a typo'd override) fails fast here.
validate_flag() {{
  case "$2" in
    0|1) ;;
    *) echo "[ERROR] $1 must be 0 or 1 (got: '$2')" >&2; exit 1 ;;
  esac
}}
validate_flag KASM_ENABLE_KASMVNC "$ENABLE_KASMVNC"
validate_flag KASM_ENABLE_XRDP "$ENABLE_XRDP"
validate_flag KASM_ENABLE_KDS "$ENABLE_KDS"
validate_flag KASM_ENABLE_IPTABLES "$ENABLE_IPTABLES"
validate_flag KASM_ENABLE_AD_JOIN "$ENABLE_AD_JOIN"
validate_flag KASM_SET_DOMAIN_FQDN "$SET_DOMAIN_FQDN"

LOG_FILE="/var/log/kasm_install.log"
mkdir -p /var/log
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
echo "===== KASM INSTALL STARTED $(date) =====" >> "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Detect OS — used by install_kasmvnc to select the right package
. /etc/os-release
OS_ID="$ID"
OS_CODENAME="${{VERSION_CODENAME:-}}"
echo "[INFO] Detected OS: $OS_ID $OS_CODENAME"

configure_iptables() {{
  echo "[INFO] Adding firewall rules at $(date)"

  # Use ufw only when it is actively enforcing; otherwise manage iptables directly.
  if systemctl is-active --quiet ufw && timeout 30 ufw status 2>/dev/null | grep -q '^Status: active$'; then
    UFW_READY=0
    for i in $(seq 1 5); do
      if timeout 30 ufw status >/dev/null 2>&1; then
        UFW_READY=1
        break
      fi
      # Wait for ufw rather than restarting it, which could disrupt its startup.
      echo "[WARN] ufw unresponsive (attempt $i/5); waiting for it to come up..."
      sleep 30
    done
    if [ "$UFW_READY" -eq 0 ]; then
      # Fail rather than ship an unreachable instance with no port rules applied.
      echo "[ERROR] ufw did not become ready after 5 attempts" >&2
      exit 1
    fi
    if [ "$ENABLE_XRDP"    -eq 1 ]; then timeout 30 ufw allow 3389/tcp || true; fi
    if [ "$ENABLE_KDS"     -eq 1 ]; then timeout 30 ufw allow 4902/tcp || true; fi
    if [ "$ENABLE_KASMVNC" -eq 1 ]; then timeout 30 ufw allow 5902/tcp || true; fi
  else
    apt install -y iptables netfilter-persistent

    if [ "$ENABLE_XRDP"    -eq 1 ]; then iptables -I INPUT -p tcp --dport 3389 -j ACCEPT; fi
    if [ "$ENABLE_KDS"     -eq 1 ]; then iptables -I INPUT -p tcp --dport 4902 -j ACCEPT; fi
    if [ "$ENABLE_KASMVNC" -eq 1 ]; then iptables -I INPUT -p tcp --dport 5902 -j ACCEPT; fi

    netfilter-persistent save
  fi
}}

apt_wait() {{
  for i in {{1..600}}; do
    if ! fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock &>/dev/null; then
      break
    fi
    printf .
    sleep 1
  done
  echo
  fuser -v /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock || true
}}

apt() {{
  local n
  for n in $(seq 1 10); do
    if command apt-get -o DPkg::Lock::Timeout=600 "$@"; then
      return 0
    fi
    echo "[WARN] apt-get failed (attempt $n/10); retrying in 30s..." >&2
    sleep 30
  done
  echo "[ERROR] apt-get failed after 10 attempts: $*" >&2
  return 1
}}

install_xfce() {{
  apt install -y supervisor xfce4 xfce4-terminal xterm xclip
}}

install_kasmvnc() {{
  cd /tmp
  KASM_VNC_PATH=/usr/share/kasmvnc
  ARCH=$(uname -m)

  case "$OS_CODENAME" in
    jammy)    KASMVNC_DISTRO="jammy" ;;    # Ubuntu 22.04
    noble)    KASMVNC_DISTRO="noble" ;;    # Ubuntu 24.04
    bullseye) KASMVNC_DISTRO="bullseye" ;; # Debian 11
    bookworm) KASMVNC_DISTRO="bookworm" ;; # Debian 12
    *)
      echo "[ERROR] KasmVNC: unsupported distro $OS_ID $OS_CODENAME" >&2
      return 1
      ;;
  esac

  if [[ "$ARCH" == "x86_64" ]]; then
    BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_${{KASMVNC_DISTRO}}_1.4.0_amd64.deb"
  else
    BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_${{KASMVNC_DISTRO}}_1.4.0_arm64.deb"
  fi

  KASM_VNC_PASSWD="$KASM_CONNECTION_PASSWORD"
  KASM_VNC_USER="$KASM_CONNECTION_USERNAME"

  wget "$BUILD_URL" -O kasmvncserver.deb
  apt install -y gettext ssl-cert libxfont2
  apt install -y /tmp/kasmvncserver.deb
  rm -f /tmp/kasmvncserver.deb
  [ ! -e $KASM_VNC_PATH/www/vnc.html ] && ln -s $KASM_VNC_PATH/www/index.html $KASM_VNC_PATH/www/vnc.html
  cd /tmp
  mkdir -p $KASM_VNC_PATH/www/Downloads
  chown -R 0:0 $KASM_VNC_PATH
  chmod -R og-w $KASM_VNC_PATH
  chown -R 1000:0 $KASM_VNC_PATH/www/Downloads
  echo -e "$KASM_VNC_PASSWD\n$KASM_VNC_PASSWD\n" | kasmvncpasswd -u $KASM_VNC_USER -w "/home/$KASM_VNC_USER/.kasmpasswd"
  chown -R 1000:0 "/home/$KASM_VNC_USER/.kasmpasswd"
  usermod -aG ssl-cert $KASM_VNC_USER || true
  su -l -c 'vncserver -select-de XFCE' $KASM_VNC_USER
}}

install_xrdp() {{
  apt install -y xrdp dbus-x11 xorg x11-xserver-utils

  usermod -aG ssl-cert xrdp || true
  systemctl enable xrdp
  systemctl restart xrdp

  sleep 1

  bash -c 'echo "xfce4-session" > /etc/skel/.xsession'
  bash -c 'echo "xfce4-session" > /etc/skel/.Xsession'
  chmod 644 /etc/skel/.xsession /etc/skel/.Xsession

  bash -c 'cat >/etc/xrdp/startwm.sh <<EOF
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
exec dbus-launch --exit-with-session xfce4-session
EOF'
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

  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    amd64) KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_amd64.deb" ;;
    arm64) KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_arm64.deb" ;;
    *) echo "[ERROR] Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac

  cd /tmp
  wget "$KDS_DEB_URL" -O kasm-desktop-service.deb

  apt install -y ./kasm-desktop-service.deb
  rm -f ./kasm-desktop-service.deb

  sleep 2

  KASM_HOST_NAME="$KASM_UPSTREAM_AUTH_ADDRESS"
  REG_TOKEN="$KASM_CHECKIN_JWT"
  API_HOST=$(echo "$KASM_HOST_NAME" | cut -d'/' -f1 | cut -d':' -f1)
  API_PORT=443

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
  apt install -y \
    realmd sssd sssd-tools adcli \
    krb5-user libpam-modules \
    samba-common-bin dnsutils \
    chrony
}}

configure_dns_for_ad() {{
  if [ -z "$AD_DNS_SERVER" ]; then
    echo "[INFO] AD_DNS_SERVER not set — relying on existing DNS to reach the domain"
    return
  fi
  echo "[INFO] Configuring DNS for AD: $AD_DNS_SERVER"
  if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1 && \
     systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat >/etc/systemd/resolved.conf.d/kasm-ad.conf <<EOF
[Resolve]
DNS=$AD_DNS_SERVER
Domains=~$AD_DOMAIN
EOF
    if ! systemctl try-restart systemd-resolved; then
      echo "[WARN] systemd-resolved restart failed — falling back to /etc/resolv.conf" >&2
      _configure_dns_resolv_conf
    fi
  else
    echo "[INFO] systemd-resolved not active — configuring DNS via /etc/resolv.conf"
    _configure_dns_resolv_conf
  fi
}}

_configure_dns_resolv_conf() {{
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
  systemctl enable --now chrony
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
    echo "[ERROR] Domain join failed"
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
  pam-auth-update --enable mkhomedir || true
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

apt_wait
sleep 10
apt_wait
apt update
apt install -y wget curl

if [ "$ENABLE_IPTABLES" -eq 1 ]; then
  configure_iptables
fi

install_xfce

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

echo "===== KASM DEB INSTALL COMPLETED $(date) ====="
