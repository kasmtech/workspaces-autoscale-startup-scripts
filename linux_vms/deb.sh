#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ENABLE_KASMVNC=0
ENABLE_XRDP=1
ENABLE_KDS=1
ENABLE_IPTABLES=1
ENABLE_AD_JOIN=0

# Provided by Kasm autoscale
AD_DOMAIN="{domain}"
AD_JOIN_PASSWORD="{ad_join_credential}"     # Kasm-generated one-time password for the machine account

# REQUIRED: set to your AD DNS server (Domain Controller IP) so the VM can resolve AD SRV records
AD_DNS_SERVER=""                            # e.g. "192.168.100.6"


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
  command apt-get -o DPkg::Lock::Timeout=600 "$@"
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

  KASM_VNC_PASSWD="{connection_password}"
  KASM_VNC_USER="{connection_username}"

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

  KASM_HOST_NAME="{upstream_auth_address}"
  REG_TOKEN="{checkin_jwt}"
  API_HOST=$(echo "$KASM_HOST_NAME" | sed -E 's@^https?://@@' | cut -d'/' -f1 | cut -d':' -f1)
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
  apt-get install -y \
    realmd sssd sssd-tools adcli \
    krb5-user oddjob oddjob-mkhomedir \
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
  printf 'nameserver %s\n' "$AD_DNS_SERVER" >"$tmp"
  grep -v "^nameserver $AD_DNS_SERVER" /etc/resolv.conf >>"$tmp" || true
  if [ -L /etc/resolv.conf ]; then
    target=$(readlink -f /etc/resolv.conf)
    echo "[INFO] /etc/resolv.conf is a symlink -> $target; writing to target to preserve link"
    cp "$tmp" "$target"
    rm -f "$tmp"
  else
    mv "$tmp" /etc/resolv.conf
  fi
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
  dig +short "_ldap._tcp.$AD_DOMAIN" SRV | grep -q '.' || {{
    echo "[ERROR] LDAP SRV records not found for $AD_DOMAIN — check AD_DNS_SERVER" >&2
    exit 1
  }}
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
      "https://{upstream_auth_address}/api/set_server_status?token={checkin_jwt}"; then
    echo "[INFO] Kasm check-in successful"
  else
    echo "[ERROR] Kasm check-in failed — server may not be marked ready in Kasm UI" >&2
  fi
}}

install_ad_join() {{
  if realm list 2>/dev/null | grep -Fiq "domain-name: $AD_DOMAIN"; then
    echo "[INFO] Already joined to $AD_DOMAIN, skipping"
    return
  fi
  install_ad_dependencies
  configure_dns_for_ad
  sync_time
  test_domain_resolution
  join_domain
  enable_homedir_creation
  echo "[INFO] AD join complete"
}}

apt_wait
sleep 10
apt_wait
apt-get update || exit 1
apt-get install -y wget curl || exit 1

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
