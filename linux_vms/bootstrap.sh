#!/usr/bin/env bash
# TEMPLATE NOTE: Python str.format() template. All brace patterns are intentional, do not alter.

set -euo pipefail

VERSION="develop"
BASE_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasm-autoscale-scripts/$VERSION"

# Per-instance values from Kasm. Substituted here only; the downloaded script reads them
# from these exported variables, so the hosted artifact contains no secrets.
export KASM_UPSTREAM_AUTH_ADDRESS="{upstream_auth_address}"
export KASM_CHECKIN_JWT="{checkin_jwt}"
export KASM_CONNECTION_USERNAME="{connection_username}"
export KASM_CONNECTION_PASSWORD="{connection_password}"
export KASM_DOMAIN="{domain}"
export KASM_AD_JOIN_CREDENTIAL="{ad_join_credential}"

# --- Optional feature overrides ----------------------------------------------
# Uncomment and set any of these to override the defaults baked into deb.sh / rpm.sh.
# Anything left unset keeps the script default. Flags are 1 (on) / 0 (off).
# export KASM_ENABLE_KASMVNC=0
# export KASM_ENABLE_XRDP=1
# export KASM_ENABLE_KDS=1
# export KASM_ENABLE_IPTABLES=1
# export KASM_ENABLE_EPEL=1                          # rpm.sh (Oracle Linux / RHEL) only
# export KASM_ENABLE_AD_JOIN=1                       # join Active Directory
# export KASM_SET_DOMAIN_FQDN=1                      # set <shortname>.<domain> FQDN before AD join
# export KASM_AD_DNS_SERVER="10.0.0.5 10.0.0.6"      # space-separated DC / AD DNS server IPs

# Select the installer for this distro family.
. /etc/os-release
case "${{ID:-}} ${{ID_LIKE:-}}" in
  *debian*|*ubuntu*)   SCRIPT="deb.sh" ;;
  *ol*|*rhel*)         SCRIPT="rpm.sh" ;;   # Oracle Linux and RHEL 8/9
  *) echo "[ERROR] Unsupported distro: ${{ID:-unknown}}" >&2; exit 1 ;;
esac

# Some minimal images ship neither curl nor wget; install one before downloading.
ensure_downloader() {{
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi
  echo "[INFO] No curl/wget found; installing curl"
  export DEBIAN_FRONTEND=noninteractive
  local n
  for n in $(seq 1 10); do
    if [ "$SCRIPT" = "deb.sh" ]; then
      if apt-get update && apt-get install -y curl; then return 0; fi
    else
      if dnf install -y curl || yum install -y curl; then return 0; fi
    fi
    echo "[WARN] installing curl failed (attempt $n/10); retrying in 10s..." >&2
    sleep 10
  done
  echo "[ERROR] could not install curl after 10 attempts" >&2
  exit 1
}}
ensure_downloader

cd /tmp
echo "[INFO] Downloading $BASE_URL/$SCRIPT"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 5 --retry-connrefused --retry-delay 5 --max-time 60 "$BASE_URL/$SCRIPT" -o "$SCRIPT"
else
  wget -q --tries=5 --waitretry=5 --timeout=60 -O "$SCRIPT" "$BASE_URL/$SCRIPT"
fi
exec bash "$SCRIPT"
