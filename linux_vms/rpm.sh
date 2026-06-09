#!/usr/bin/env bash
set -euo pipefail

ENABLE_KASMVNC=0
ENABLE_XRDP=1
ENABLE_KDS=1
ENABLE_EPEL=1
ENABLE_IPTABLES=1

LOG_FILE="/var/log/kasm_install.log"
mkdir -p /var/log
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
echo "===== KASM RPM INSTALL STARTED $(date) =====" >> "$LOG_FILE"
exec > >(stdbuf -oL -eL tee -a "$LOG_FILE") 2>&1

# Detect OS — used by install_epel and install_kasmvnc
. /etc/os-release
OS_ID="$ID"
OS_MAJOR=$(echo "$VERSION_ID" | cut -d'.' -f1)
echo "[INFO] Detected OS: $OS_ID $OS_MAJOR"

# Wrap every dnf call so it waits for the package-manager lock (held by
# oracle-cloud-agent plugin installs and Oracle Autonomous Linux auto-patching at
# boot) instead of hanging indefinitely or aborting. Also retries flaky downloads.
dnf() {{
  command dnf --setopt=lock_timeout=600 --setopt=retries=10 "$@"
}}

configure_iptables() {{
  echo "[INFO] Adding firewall rules at $(date)"

  if systemctl is-active --quiet firewalld; then
    # firewall-cmd talks to firewalld over D-Bus, which is unreliable early in boot
    # on Oracle (Autonomous) Linux: the daemon reports active(running) yet
    # firewall-cmd hangs on every D-Bus call, and restarting the daemon does not
    # clear it. Configure the firewall WITHOUT D-Bus instead: stop firewalld, write
    # the ports straight to the permanent config with firewall-offline-cmd (no daemon
    # / no D-Bus needed), then start it so it loads them on boot. Deterministic.
    systemctl stop firewalld || true

    if [ "$ENABLE_XRDP"    -eq 1 ]; then firewall-offline-cmd --add-port=3389/tcp || true; fi
    if [ "$ENABLE_KDS"     -eq 1 ]; then firewall-offline-cmd --add-port=4902/tcp || true; fi
    if [ "$ENABLE_KASMVNC" -eq 1 ]; then firewall-offline-cmd --add-port=5902/tcp || true; fi

    systemctl enable firewalld || true
    systemctl start firewalld || echo "[WARN] firewalld failed to start; host firewall rules may not be active" >&2
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
      # Enable CodeReady Linux Builder — required for some EPEL package dependencies on RHEL
      if [ "$OS_MAJOR" -ge 9 ]; then
        dnf config-manager --enable crb || true
      else
        dnf config-manager --enable powertools || true
      fi
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
      return 1
    fi
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
  getent group ssl-cert >/dev/null 2>&1 && usermod -aG ssl-cert "$KASM_VNC_USER" || true

  su -l -c 'vncserver -select-de XFCE' $KASM_VNC_USER
}}

install_xrdp() {{
  # Precheck: verify xrdp is available; if not, EPEL must be enabled
  if ! dnf list available xrdp &>/dev/null; then
    if [ "$ENABLE_EPEL" -eq 0 ]; then
      echo "[ERROR] xrdp is not available in configured repos. Set ENABLE_EPEL=1 to install EPEL first." >&2
      return 1
    fi
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
exec xfce4-session
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
  if [[ "$ARCH" == "x86_64" ]]; then
    KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_amd64.rpm"
  else
    KDS_RPM_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_desktop_service/kasm-desktop-service_0.0%2Bdevelop_arm64.rpm"
  fi

  cd /tmp
  wget "$KDS_RPM_URL" -O kasm-desktop-service.rpm

  dnf install -y ./kasm-desktop-service.rpm
  rm -f kasm-desktop-service.rpm

  sleep 2

  KASM_HOST_NAME="{upstream_auth_address}"
  REG_TOKEN="{checkin_jwt}"
  API_HOST=$(echo "$KASM_HOST_NAME" | sed -E 's@^https?://@@' | cut -d'/' -f1 | cut -d':' -f1)
  API_PORT=443

  # Bound the check-in callback: if the deployment/proxy is unreachable this would
  # otherwise hang forever with no timeout, and the server would never check in.
  timeout 300 /opt/kasm-desktop-service/scripts/register_wizard.sh \
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

sleep 5

dnf install -y wget || exit 1

# iptables-services is in base/appstream repos, so firewall setup runs before EPEL is configured
if [ "$ENABLE_IPTABLES" -eq 1 ]; then
  configure_iptables || exit 1
fi

if [ "$ENABLE_EPEL" -eq 1 ]; then
  install_epel || exit 1
fi

install_xfce || exit 1
install_screenshot_tools || true

if [ "$ENABLE_KASMVNC" -eq 1 ]; then
  install_kasmvnc || exit 1
fi

if [ "$ENABLE_XRDP" -eq 1 ]; then
  install_xrdp || exit 1
fi

if [ "$ENABLE_KDS" -eq 1 ]; then
  install_kds || exit 1
fi

echo "===== KASM RPM INSTALL COMPLETED $(date) ====="
