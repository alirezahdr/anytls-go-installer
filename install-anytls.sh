#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export LC_ALL=C

readonly REPO_API='https://api.github.com/repos/anytls/anytls-go/releases/latest'
readonly PANEL_URL='https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/anytls-panel.sh'
readonly USERS_HELPER_URL='https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/anytls-users.py'
readonly PANEL_FILE='/usr/local/bin/anytls-panel'
readonly USERS_HELPER_FILE='/usr/local/bin/anytls-users.py'
readonly SERVICE_NAME='anytls'
readonly SERVICE_FILE='/etc/systemd/system/anytls.service'
readonly ANYTLS_DROPIN_DIR='/etc/systemd/system/anytls.service.d'
readonly TUNNEL_DROPIN_DIR='/etc/systemd/system/anytls-tunnel.service.d'
readonly CONFIG_DIR='/etc/anytls'
readonly CONFIG_FILE='/etc/anytls/anytls.env'
readonly BIN_FILE='/usr/local/bin/anytls-server'
readonly WRAPPER_FILE='/usr/local/libexec/anytls-server-start'

TMP_DIR=''
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

ensure_qrencode() {
  command -v qrencode >/dev/null 2>&1 && return 0
  printf 'Installing qrencode, required for AnyTLS QR exports...\n'
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update || return 1
    apt-get install -y qrencode || return 1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y qrencode || return 1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y qrencode || return 1
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install qrencode || return 1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache qrencode || return 1
  else
    printf 'No supported package manager found to install qrencode.\n' >&2
    return 1
  fi
  command -v qrencode >/dev/null 2>&1
}

for command_name in curl python3 base64 systemctl useradd getent install id; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
done

[[ "$(uname -s)" == 'Linux' ]] || die 'This installer supports Linux only.'
[[ "$EUID" -eq 0 ]] || die 'Run this script as root: sudo bash install-anytls.sh'
[[ -d /run/systemd/system ]] || die 'systemd is not active. This installer requires systemd.'

TMP_DIR="$(mktemp -d -t anytls-install.XXXXXXXX)"
chmod 0700 "$TMP_DIR"
printf 'Installing the terminal control panel...\n'
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 60 \
  "$PANEL_URL" --output "$TMP_DIR/anytls-panel"
install -o root -g root -m 0755 "$TMP_DIR/anytls-panel" "$PANEL_FILE"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 60 \
  "$USERS_HELPER_URL" --output "$TMP_DIR/anytls-users.py"
install -o root -g root -m 0755 "$TMP_DIR/anytls-users.py" "$USERS_HELPER_FILE"

dropin_changed=0
for service_dropin in "anytls:$ANYTLS_DROPIN_DIR" "anytls-tunnel:$TUNNEL_DROPIN_DIR"; do
  service_name="${service_dropin%%:*}"
  dropin_dir="${service_dropin#*:}"
  if systemctl cat "$service_name" >/dev/null 2>&1; then
    install -d -o root -g root -m 0755 "$dropin_dir"
    cat > "$TMP_DIR/netlink.conf" <<'UNIT'
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
UNIT
    install -o root -g root -m 0644 "$TMP_DIR/netlink.conf" "$dropin_dir/zz-netlink.conf"
    dropin_changed=1
  fi
done
if (( dropin_changed )); then
  systemctl daemon-reload
  printf 'Updated existing service restrictions to allow the required netlink socket family. Restart the affected service to apply the change.\n'
fi

printf '\nChoose what to configure on this server:\n'
printf '1) Install or reconfigure the AnyTLS server\n'
printf '2) Set up direct Iran-to-abroad TCP forwarding with GOST\n'
printf '3) Open the service control panel\n'
printf '0) Exit\n'
while true; do
  read -r -p 'Select an option: ' install_mode
  case "$install_mode" in
    1) break ;;
    2) "$PANEL_FILE" --setup-forward; exit ;;
    3)
      if systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
        ensure_qrencode || die 'Could not install qrencode. Install it with your Linux package manager, then reopen the panel.'
      fi
      "$PANEL_FILE"
      exit
      ;;
    0) exit 0 ;;
    *) printf 'Invalid option. Enter 1, 2, 3, or 0.\n' >&2 ;;
  esac
done

ensure_qrencode || die 'Could not install qrencode. AnyTLS installation stopped; install qrencode with your Linux package manager and retry.'

if [[ -s /etc/anytls/users.json ]]; then
  printf '\nMulti-user sing-box mode is already configured. Opening the control panel without replacing the server backend.\n'
  "$PANEL_FILE"
  exit 0
fi

if [[ -e "$SERVICE_FILE" || -e "$CONFIG_FILE" || -e "$BIN_FILE" ]]; then
  printf 'An existing AnyTLS installation was found. Continuing will replace its IP, port, and password settings.\n'
  read -r -p 'Type yes to continue and reconfigure: ' replace_existing
  [[ "$replace_existing" == 'yes' ]] || die 'Operation cancelled.'
fi

if [[ -t 0 ]]; then
  read -r -p 'Server listen IP [0.0.0.0 for all IPv4 interfaces]: ' SERVER_IP
else
  die 'Run this script from an interactive terminal to enter the IP, port, and password.'
fi
SERVER_IP="${SERVER_IP:-0.0.0.0}"

if ! SERVER_IP="$(python3 - "$SERVER_IP" <<'PY'
import ipaddress
import sys

try:
    print(ipaddress.ip_address(sys.argv[1]).compressed)
except ValueError:
    raise SystemExit("Invalid IP address. Enter an IPv4 or IPv6 address.")
PY
)"; then
  die 'Invalid IP address.'
fi

while true; do
  read -r -p 'AnyTLS port [for example, 443 or 8443]: ' PORT
  if [[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$PORT >= 1 && 10#$PORT <= 65535 )); then
    PORT=$((10#$PORT))
    break
  fi
  printf 'The port must be a number between 1 and 65535.\n' >&2
done

while true; do
  read -r -s -p 'AnyTLS password (at least 16 characters): ' PASSWORD
  printf '\n'
  read -r -s -p 'Confirm password: ' PASSWORD_CONFIRM
  printf '\n'
  if (( ${#PASSWORD} < 16 )); then
    printf 'The password must contain at least 16 characters.\n' >&2
  elif [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
    printf 'The passwords do not match.\n' >&2
  else
    break
  fi
done
unset PASSWORD_CONFIRM

case "$(uname -m)" in
  x86_64|amd64) ARCH='amd64' ;;
  aarch64|arm64) ARCH='arm64' ;;
  *) die "Architecture $(uname -m) is not supported by the official releases. Supported architectures: amd64 and arm64." ;;
esac

printf 'Fetching the latest official AnyTLS-Go release information from GitHub...\n'
curl --fail --silent --show-error --location \
  --retry 3 --connect-timeout 15 --max-time 60 \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --user-agent 'anytls-go-installer' \
  "$REPO_API" --output "$TMP_DIR/release.json"

mapfile -t RELEASE_INFO < <(python3 - "$TMP_DIR/release.json" "$ARCH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    release = json.load(stream)

tag = release.get("tag_name", "")
if not tag or release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub did not return a valid stable release.")

version = tag[1:] if tag.startswith("v") else tag
expected_name = f"anytls_{version}_linux_{sys.argv[2]}.zip"
matches = [asset for asset in release.get("assets", []) if asset.get("name") == expected_name]
if len(matches) != 1:
    raise SystemExit(f"Official release asset not found: {expected_name}")

asset = matches[0]
url = asset.get("browser_download_url", "")
if not url.startswith("https://github.com/anytls/anytls-go/releases/download/"):
    raise SystemExit("The release download URL is unexpected.")

digest = asset.get("digest", "") or ""
if digest and not digest.startswith("sha256:"):
    raise SystemExit("The checksum type provided by GitHub is not supported.")

print(tag)
print(url)
print(digest.split(":", 1)[1] if digest else "")
PY
)

(( ${#RELEASE_INFO[@]} == 3 )) || die 'Could not read release information from GitHub.'
VERSION="${RELEASE_INFO[0]}"
DOWNLOAD_URL="${RELEASE_INFO[1]}"
EXPECTED_SHA256="${RELEASE_INFO[2]}"
[[ "$VERSION" =~ ^v?[0-9A-Za-z._-]+$ ]] || die 'GitHub returned an invalid version number.'
printf 'Selected version %s for Linux/%s.\n' "$VERSION" "$ARCH"

ARCHIVE="$TMP_DIR/anytls.zip"
curl --fail --silent --show-error --location \
  --retry 3 --connect-timeout 15 --max-time 300 \
  --user-agent 'anytls-go-installer' \
  "$DOWNLOAD_URL" --output "$ARCHIVE"

SERVER_STAGE="$TMP_DIR/anytls-server"
python3 - "$ARCHIVE" "$EXPECTED_SHA256" "$SERVER_STAGE" <<'PY'
import hashlib
import os
import stat
import sys
import zipfile

archive_path, expected_digest, output_path = sys.argv[1:]
digest = hashlib.sha256()
with open(archive_path, "rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
if expected_digest and digest.hexdigest().lower() != expected_digest.lower():
    raise SystemExit("The downloaded file does not match the SHA-256 checksum provided by GitHub.")

try:
    with zipfile.ZipFile(archive_path) as package:
        candidates = [item for item in package.infolist()
                      if item.filename.rsplit("/", 1)[-1] == "anytls-server" and not item.is_dir()]
        if len(candidates) != 1:
            raise SystemExit("Could not find exactly one anytls-server binary in the archive.")
        member = candidates[0]
        mode = member.external_attr >> 16
        if stat.S_ISLNK(mode):
            raise SystemExit("The server binary in the archive is a symlink. Installation stopped.")
        with package.open(member) as source, open(output_path, "wb") as target:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                target.write(chunk)
except (OSError, zipfile.BadZipFile) as error:
    raise SystemExit(f"The downloaded archive is invalid: {error}")

if os.path.getsize(output_path) == 0:
    raise SystemExit("The downloaded executable is empty.")
PY
chmod 0755 "$SERVER_STAGE"

if ! getent passwd anytls >/dev/null 2>&1; then
  NOLOGIN="$(command -v nologin || true)"
  if [[ -z "$NOLOGIN" ]]; then
    [[ -x /usr/sbin/nologin ]] && NOLOGIN='/usr/sbin/nologin'
    [[ -x /sbin/nologin ]] && NOLOGIN='/sbin/nologin'
  fi
  NOLOGIN="${NOLOGIN:-/bin/false}"
  useradd --system --no-create-home --home-dir /nonexistent --shell "$NOLOGIN" anytls
fi
[[ "$(id -u anytls)" != '0' ]] || die 'The anytls system account has UID 0. Installation stopped.'

if [[ "$SERVER_IP" == *:* ]]; then
  LISTEN="[$SERVER_IP]:$PORT"
else
  LISTEN="$SERVER_IP:$PORT"
fi
PASSWORD_B64="$(printf '%s' "$PASSWORD" | base64 | tr -d '\n')"
unset PASSWORD

printf 'Installing files and creating the systemd service...\n'
if systemctl is-active --quiet "$SERVICE_NAME"; then
  systemctl stop "$SERVICE_NAME"
fi

install -d -o root -g root -m 0755 /usr/local/bin /usr/local/libexec "$CONFIG_DIR"
install -o root -g root -m 0755 "$SERVER_STAGE" "$BIN_FILE.new"
mv -f -- "$BIN_FILE.new" "$BIN_FILE"

cat > "$TMP_DIR/anytls-server-start" <<'SH'
#!/bin/sh
set -eu
listen="${ANYTLS_LISTEN:?ANYTLS_LISTEN is not set}"
encoded_password="${ANYTLS_PASSWORD_B64:?Password is not set}"
password="$(printf '%s' "$encoded_password" | base64 -d)"
unset ANYTLS_PASSWORD_B64 encoded_password
exec /usr/local/bin/anytls-server -l "$listen" -p "$password"
SH
install -o root -g root -m 0755 "$TMP_DIR/anytls-server-start" "$WRAPPER_FILE.new"
mv -f -- "$WRAPPER_FILE.new" "$WRAPPER_FILE"

printf 'ANYTLS_LISTEN=%s\nANYTLS_PASSWORD_B64=%s\n' "$LISTEN" "$PASSWORD_B64" > "$TMP_DIR/anytls.env"
unset PASSWORD_B64
install -o root -g root -m 0600 "$TMP_DIR/anytls.env" "$CONFIG_FILE.new"
mv -f -- "$CONFIG_FILE.new" "$CONFIG_FILE"

cat > "$TMP_DIR/anytls.service" <<'UNIT'
[Unit]
Description=AnyTLS-Go Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=anytls
EnvironmentFile=/etc/anytls/anytls.env
ExecStart=/usr/local/libexec/anytls-server-start
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT
install -o root -g root -m 0644 "$TMP_DIR/anytls.service" "$SERVICE_FILE.new"
mv -f -- "$SERVICE_FILE.new" "$SERVICE_FILE"

systemctl daemon-reload
if ! systemctl enable --now "$SERVICE_NAME"; then
  printf 'The service failed to start. Recent logs:\n' >&2
  systemctl status "$SERVICE_NAME" --no-pager >&2 || true
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager >&2 || true
  die 'The service was installed but could not be started. Review the logs above.'
fi
systemctl is-active --quiet "$SERVICE_NAME" || die 'The service did not become active after installation.'

printf '\nAnyTLS-Go %s installation is complete.\n' "$VERSION"
printf 'Listen address: %s\n' "$LISTEN"
printf 'Service status: '
systemctl is-active "$SERVICE_NAME"
printf '\nOpening the terminal control panel...\n'
"$PANEL_FILE"
