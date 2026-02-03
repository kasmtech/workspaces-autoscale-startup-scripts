#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ENABLE_KASMVNC=0
ENABLE_XRDP=1
ENABLE_KDS=1
ENABLE_IPTABLES=1
ENABLE_AD_JOIN=1

# provided by Kasm workspace
AD_DOMAIN="{domain}"
AD_JOIN_PASSWORD="{ad_join_credential}"     # only a password from Kasm

AD_JOIN_USER="change_me"                # must be modified separately as per user as the delegated join account 

# DNS_SERVERS intentionally unused – AD DNS is discovered dynamically
DNS_SERVERS="change_me" # optional
SERVER_NAME="change_me" # optional

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

  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_amd64.deb"
  else
    KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_arm64.deb"
  fi

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
    samba-common-bin dnsutils
}}

cleanup() {{
  restore_dns || true
}}
trap cleanup EXIT

backup_dns() {{
  if [ -e /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf /etc/resolv.conf.pre-ad
  fi
}}

configure_dns_for_ad() {{
  echo "[INFO] Temporarily overriding DNS for AD join"

  systemctl disable systemd-resolved --now || true
  rm -f /etc/resolv.conf

  cat >/etc/resolv.conf <<EOF
nameserver $DC_IP
search $AD_DOMAIN
EOF
}}

restore_dns() {{
  if [ -f /etc/resolv.conf.pre-ad ]; then
    echo "[INFO] Restoring original DNS configuration"
    rm -f /etc/resolv.conf
    mv /etc/resolv.conf.pre-ad /etc/resolv.conf
    systemctl enable systemd-resolved --now || true
  fi
}}

test_domain_resolution() {{
  echo "[INFO] Testing DNS resolution for $AD_DOMAIN"

  if [ -z "$(dig +short "$AD_DOMAIN" | head -n1)" ]; then
    echo "[ERROR] Domain $AD_DOMAIN not resolvable"
    exit 1
  fi

  realm discover "$AD_DOMAIN" >/dev/null || {{
    echo "[ERROR] realm discovery failed for $AD_DOMAIN"
    exit 1
  }}

  echo "[INFO] Domain resolution successful"
}}

set_hostname() {{
  if [ -n "$SERVER_NAME" ]; then
    echo "[INFO] Setting hostname to $SERVER_NAME"
    hostnamectl set-hostname "$SERVER_NAME"
  fi
}}

discover_dc() {{
  echo "[INFO] Discovering DC via DNS SRV"
  DC_HOST=$(dig +short _kerberos._tcp."$AD_DOMAIN" SRV | awk '{print $4}' | head -n1 | sed 's/\.$//')
  if [ -z "$DC_HOST" ]; then
    echo "[ERROR] Unable to discover DC hostname"
    exit 1
  fi
  DC_IP=$(getent hosts "$DC_HOST" | awk '{print $1}' | head -n1)
  if [ -z "$DC_IP" ]; then
    echo "[ERROR] Unable to resolve DC IP"
    exit 1
  fi
  echo "[INFO] Using DC $DC_HOST ($DC_IP)"
}}

sync_time() {{
  echo "[INFO] Syncing time with DC"
  apt-get install -y ntpdate || true
  ntpdate "$DC_IP" || true
}}

join_domain() {{
  echo "[INFO] Joining domain $AD_DOMAIN"
  echo "$AD_JOIN_PASSWORD" | realm join "$AD_DOMAIN" \
    --user="$AD_JOIN_USER" \
    --membership-software=adcli \
    --unattended || {{
      echo "[ERROR] Domain join failed"
      exit 1
    }}
  echo "[INFO] Domain join successful"
}}

enable_homedir_creation() {{
  pam-auth-update --enable mkhomedir || true
  systemctl enable sssd
  systemctl restart sssd
}}

install_ad_join()
{{

  if realm list | grep -qi "$AD_DOMAIN"; then
    echo "[INFO] Already joined to $AD_DOMAIN, skipping AD join"
    return
  fi
  install_ad_dependencies
  set_hostname
  discover_dc
  backup_dns
  configure_dns_for_ad
  sync_time
  test_domain_resolution
  join_domain
  restore_dns
  enable_homedir_creation

  echo "[INFO] AD Join complete — rebooting"
  sleep 3 
  reboot
}}

apt_wait
sleep 10
apt_wait
apt update
apt install -y wget

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

echo "===== KASM DEB INSTALL COMPLETED $(date) ====="
