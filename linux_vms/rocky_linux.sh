#!/usr/bin/env bash
set -ex

ENABLE_KASMVNC=1
ENABLE_XRDP=1
ENABLE_KDS=1

LOG_FILE="/var/log/kasm_install.log"
mkdir -p /var/log
echo "===== KASM RPM INSTALL STARTED $(date) =====" >> "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

configure_iptables() {
  echo "[INFO] Adding firewall rules for RDP (3389) and Kasm (4902)"

  if systemctl is-active --quiet firewalld; then
    firewall-cmd --add-port=3389/tcp --permanent
    firewall-cmd --add-port=4902/tcp --permanent
    firewall-cmd --reload
  else
    iptables -I INPUT -p tcp --dport 3389 -j ACCEPT
    iptables -I INPUT -p tcp --dport 4902 -j ACCEPT
  fi
}

# this is for RHEL based OS
dnf -y update
dnf -y install epel-release
dnf config-manager --set-enabled crb || true

install_xfce() {
  dnf groupinstall -y "Xfce"
  dnf install -y \
    supervisor \
    xfce4-terminal \
    xterm \
    xclip \
    dbus-x11 \
    xorg-x11-xauth \
    xorg-x11-server-Xorg
}

# Optional:  screenshot tooling
install_screenshot_tools() {
  if dnf install -y gnome-screenshot; then
    echo "[INFO] gnome-screenshot installed successfully"
  else
    echo "[WARN] gnome-screenshot not available; screenshot API may be limited on this system"
  fi
}

install_kasmvnc() {
  cd /tmp

  KASM_VNC_PATH=/usr/share/kasmvnc
  BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.3.3/kasmvncserver_el9_1.3.3_x86_64.rpm"
  KASM_VNC_PASSWD="{connection_password}"
  KASM_VNC_USER="{connection_username}"

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
  usermod -aG ssl-cert $KASM_VNC_USER || true

  su -l -c 'vncserver -select-de XFCE' $KASM_VNC_USER
}

install_xrdp() {
  dnf install -y xrdp

  systemctl enable xrdp
  systemctl restart xrdp

  echo "xfce4-session" > /etc/skel/.xsession
  echo "xfce4-session" > /etc/skel/.Xsession

  cat >/etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
exec xfce4-session
EOF

  chmod +x /etc/xrdp/startwm.sh

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
}

install_kds() {
  cd /tmp

  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0+develop_x86_64.rpm"
  else
    KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0+develop_aarch64.rpm"
  fi

  wget "$KDS_RPM_URL" -O kasm-desktop-service.rpm
  SKIP_KASM_REGISTRATION=1 dnf install -y ./kasm-desktop-service.rpm
  rm -f kasm-desktop-service.rpm

  KASM_HOST_NAME="{upstream_auth_address}"
  REG_TOKEN="{checkin_jwt}"

  API_HOST=$(echo "$KASM_HOST_NAME" | sed -E 's@^https?://@@' | cut -d':' -f1)
  API_PORT=443

  /opt/kasm-desktop-service/scripts/register_wizard.sh \
    --register \
    --no-gui \
    --api-host="$API_HOST" \
    --api-port="$API_PORT" \
    --token="$REG_TOKEN"

  systemctl enable kasm-desktop.service
  systemctl restart kasm-desktop.service
}

install_xfce
install_screenshot_tools

if [ "$ENABLE_KASMVNC" -eq 1 ]; then
  install_kasmvnc
fi

if [ "$ENABLE_XRDP" -eq 1 ]; then
  install_xrdp
fi

if [ "$ENABLE_KDS" -eq 1 ]; then
  install_kds
fi

echo "===== KASM RPM INSTALL COMPLETED $(date) ====="
