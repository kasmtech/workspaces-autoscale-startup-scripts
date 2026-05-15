#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ENABLE_KASMVNC=0
ENABLE_XRDP=1
ENABLE_KDS=1
ENABLE_IPTABLES=1

LOG_FILE="/var/log/kasm_install.log"
mkdir -p /var/log
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
echo "===== KASM INSTALL STARTED $(date) =====" >> "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Detect OS — used by install_kasmvnc to select the right package
. /etc/os-release
OS_ID="$ID"
OS_CODENAME="$VERSION_CODENAME"
echo "[INFO] Detected OS: $OS_ID $OS_CODENAME"

configure_iptables() {{
  echo "[INFO] Adding firewall rules at $(date)"

  if systemctl is-active --quiet ufw; then
    for i in 1 2 3 4 5; do
      ufw status >/dev/null 2>&1 && break
      sleep 3
    done
    [ "$ENABLE_XRDP"    -eq 1 ] && ufw allow 3389/tcp
    [ "$ENABLE_KDS"     -eq 1 ] && ufw allow 4902/tcp
    [ "$ENABLE_KASMVNC" -eq 1 ] && ufw allow 5902/tcp
  else
    apt-get install -y iptables netfilter-persistent

    [ "$ENABLE_XRDP"    -eq 1 ] && iptables -I INPUT -p tcp --dport 3389 -j ACCEPT
    [ "$ENABLE_KDS"     -eq 1 ] && iptables -I INPUT -p tcp --dport 4902 -j ACCEPT
    [ "$ENABLE_KASMVNC" -eq 1 ] && iptables -I INPUT -p tcp --dport 5902 -j ACCEPT

    netfilter-persistent save
  fi
}}

apt_wait () {{
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
    while fuser /var/log/unattended-upgrades/unattended-upgrades.log >/dev/null 2>&1 ; do
      sleep 1
    done
  fi
}}

install_xfce (){{
  apt-get install -y supervisor xfce4 xfce4-terminal xterm xclip
}}

install_kasmvnc (){{
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
  apt-get install -y gettext ssl-cert libxfont2
  apt-get install -y /tmp/kasmvncserver.deb
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

install_xrdp () {{
  apt-get install -y xrdp dbus-x11 xorg x11-xserver-utils

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

install_kds () {{

  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_amd64.deb"
  else
    KDS_DEB_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_arm64.deb"
  fi

  cd /tmp
  wget "$KDS_DEB_URL" -O kasm-desktop-service.deb

  apt-get install -y ./kasm-desktop-service.deb
  rm -f ./kasm-desktop-service.deb

  sleep 2

  KASM_HOST_NAME="{upstream_auth_address}"
  REG_TOKEN="{checkin_jwt}"
  API_HOST=$(echo "$KASM_HOST_NAME" | sed -E 's@^https?://@@' | cut -d'/' -f1 | cut -d':' -f1)
  API_PORT=443

  bash /opt/kasm-desktop-service/scripts/register_wizard.sh \
    --register \
    --no-gui \
    --api-host="$API_HOST" \
    --api-port="$API_PORT" \
    --token="$REG_TOKEN"

  sleep 2

  systemctl enable kasm-desktop.service
  systemctl restart kasm-desktop.service || systemctl start kasm-desktop.service
}}

apt_wait
sleep 10
apt_wait
apt-get update
apt-get install -y wget

[ "$ENABLE_IPTABLES" -eq 1 ] && configure_iptables

install_xfce

if [ "$ENABLE_KASMVNC" -eq 1 ]; then
  install_kasmvnc
fi

if [ "$ENABLE_XRDP" -eq 1 ]; then
  install_xrdp
fi

if [ "$ENABLE_KDS" -eq 1 ]; then
  install_kds
fi

echo "===== KASM DEB INSTALL COMPLETED $(date) ====="
