#!/usr/bin/env bash
# Renders deb.sh / rpm.sh into dist/ for hosting (blanks {tokens}, collapses {{ }}).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"   # linux_vms/
DIST_DIR="$PROJECT_ROOT/dist"

# Per-instance Kasm tokens supplied by the bootstrap via KASM_* env vars instead.
TOKENS=(domain ad_join_credential connection_password connection_username upstream_auth_address checkin_jwt server_hostname)

render() {
  local src="$1" dst="$2" t
  local sed_args=()
  for t in "${TOKENS[@]}"; do
    sed_args+=(-e "s/{$t}//g")
  done
  # Blank tokens first, THEN collapse doubled braces (order matters for ${{X:-{token}}}).
  sed "${sed_args[@]}" -e 's/{{/{/g' -e 's/}}/}/g' "$src" > "$dst"
  chmod +x "$dst"
}

mkdir -p "$DIST_DIR"
echo "=== Rendering Linux startup scripts -> $DIST_DIR ==="
for name in deb rpm; do
  src="$PROJECT_ROOT/$name.sh"
  dst="$DIST_DIR/$name.sh"
  [ -f "$src" ] || { echo "[ERROR] missing $src" >&2; exit 1; }
  render "$src" "$dst"

  # Fail the build if the rendered output is not valid bash.
  if ! bash -n "$dst"; then
    echo "[ERROR] rendered $name.sh is not valid bash" >&2
    exit 1
  fi
  # Fail if any unrendered template artifact slipped through.
  token_pattern=$(IFS='|'; echo "${TOKENS[*]}")
  if grep -nE "\\{\\{|\\}\\}|\\{($token_pattern)\\}" "$dst"; then
    echo "[ERROR] unrendered template artifacts remain in $name.sh (see above)" >&2
    exit 1
  fi
  echo "  OK  $name.sh ($(wc -c < "$dst") bytes)"
done
echo "=== Build complete ==="
