#!/usr/bin/env bash
set -ex
export DEBIAN_FRONTEND=noninteractive

apt_wait () {{
  while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
    while sudo fuser /var/log/unattended-upgrades/unattended-upgrades.log >/dev/null 2>&1 ; do
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
  BUILD_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.3.3/kasmvncserver_focal_1.3.3_amd64.deb"
  KASM_VNC_PASSWD={connection_password}
  KASM_VNC_USER={connection_username}
  wget "$BUILD_URL" -O kasmvncserver.deb
  apt-get install -y gettext ssl-cert libxfont2
  apt-get install -y /tmp/kasmvncserver.deb
  rm -f /tmp/kasmvncserver.deb
  ln -s $KASM_VNC_PATH/www/index.html $KASM_VNC_PATH/www/vnc.html
  cd /tmp
  mkdir -p $KASM_VNC_PATH/www/Downloads
  chown -R 0:0 $KASM_VNC_PATH
  chmod -R og-w $KASM_VNC_PATH
  chown -R 1000:0 $KASM_VNC_PATH/www/Downloads
  echo -e "$KASM_VNC_PASSWD\n$KASM_VNC_PASSWD\n" | kasmvncpasswd -u $KASM_VNC_USER -w "/home/$KASM_VNC_USER/.kasmpasswd"
  chown -R 1000:0 "/home/$KASM_VNC_USER/.kasmpasswd"
  addgroup $KASM_VNC_USER ssl-cert
  su -l -c 'vncserver -select-de XFCE' $KASM_VNC_USER
}}

install_tigervnc (){{
  apt-get install -y tigervnc-standalone-server
  mkdir /home/ubuntu/.vnc
  echo "password123abc" | vncpasswd -f > /home/ubuntu/.vnc/passwd
  echo -e "#!/bin/sh\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nexec startxfce4" >> /home/ubuntu/.vnc/xstartup
  chown -R ubuntu:ubuntu /home/ubuntu/.vnc
  chmod 0600 /home/ubuntu/.vnc/passwd
  su -l -c 'vncserver -localhost no' ubuntu
}}

apt_wait
sleep 10
apt_wait
apt-get update
install_xfce
install_kasmvnc
#install_tigervnc
