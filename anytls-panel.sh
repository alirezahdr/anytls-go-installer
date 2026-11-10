#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export LC_ALL=C

readonly ANYTLS_UNIT='anytls'
readonly ANYTLS_CONFIG='/etc/anytls/anytls.env'
readonly TUNNEL_UNIT='anytls-tunnel'
readonly TUNNEL_USER='anytls-tunnel'
readonly TUNNEL_DIR='/etc/anytls-tunnel'
readonly TUNNEL_CONFIG='/etc/anytls-tunnel/forward.env'
readonly TUNNEL_WRAPPER='/usr/local/libexec/anytls-tunnel-start'
readonly TUNNEL_SERVICE_FILE='/etc/systemd/system/anytls-tunnel.service'
readonly GOST_API='https://api.github.com/repos/go-gost/gost/releases/latest'
readonly GOST_BIN='/usr/local/bin/anytls-gost'

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
RESET=$'\033[0m'
TMP_DIR=''
TUNNEL_GROUP=''

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

fail() {
  printf '%sError: %s%s\n' "$RED" "$*" "$RESET" >&2
}

pause() {
  printf '\n'
  read -r -p 'Press Enter to continue... ' _
}

header() {
  printf '\033[2J\033[H'
  printf '%s==============================================%s\n' "$CYAN" "$RESET"
  printf '%s           AnyTLS Control Panel%s\n' "$GREEN" "$RESET"
  printf '%s==============================================%s\n\n' "$CYAN" "$RESET"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
    fail 'Run this panel as root or through sudo.'
    exit 1
  fi
  command -v systemctl >/dev/null 2>&1 || { fail 'systemctl is required.'; exit 1; }
}

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ip() {
  python3 - "$1" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys
ipaddress.ip_address(sys.argv[1])
PY
}

valid_host() {
  python3 - "$1" >/dev/null 2>&1 <<'PY'
import ipaddress
import re
import sys
value = sys.argv[1]
try:
    ipaddress.ip_address(value)
except ValueError:
    label = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    if len(value) > 253 or not re.fullmatch(label + r"(?:\." + label + r")*\.?", value):
        raise SystemExit(1)
PY
}

read_valid() {
  local prompt="$1" default="$2" validator="$3" target="$4" value
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "$prompt [$default]: " value
      if [[ -z "$value" ]]; then value="$default"; fi
    else
      read -r -p "$prompt: " value
    fi
    if "$validator" "$value"; then
      printf -v "$target" '%s' "$value"
      return 0
    fi
    printf '%sInvalid value. Please try again.%s\n' "$YELLOW" "$RESET" >&2
  done
}

ask_password() {
  local first second length
  while true; do
    read -r -s -p 'AnyTLS password (at least 16 characters): ' first
    printf '\n'
    read -r -s -p 'Confirm password: ' second
    printf '\n'
    length="$(printf '%s' "$first" | wc -m)"
    if (( length < 16 )); then
      printf '%sThe password must contain at least 16 characters.%s\n' "$YELLOW" "$RESET"
    elif [[ "$first" != "$second" ]]; then
      printf '%sThe passwords do not match.%s\n' "$YELLOW" "$RESET"
    else
      REPLY="$first"
      unset second
      return 0
    fi
    unset first second
  done
}

unit_installed() {
  systemctl cat "$1" >/dev/null 2>&1
}

unit_state() {
  local state
  if ! unit_installed "$1"; then
    printf 'not installed'
    return
  fi
  state="$(systemctl is-active "$1" 2>/dev/null || true)"
  printf '%s' "${state:-inactive}"
}

forward_state() {
  if [[ -r "$TUNNEL_CONFIG" ]] && grep -q '^SSH_HOST=' "$TUNNEL_CONFIG"; then
    printf 'legacy SSH setup; reconfigure'
  else
    unit_state "$TUNNEL_UNIT"
  fi
}

unit_menu() {
  local unit="$1" label="$2" choice action
  while true; do
    header
    printf '%sService: %s%s\n\n' "$GREEN" "$label" "$RESET"
    printf '1) Status\n2) Start\n3) Stop\n4) Restart\n5) Enable at boot\n6) Disable at boot\n7) Recent logs\n8) Follow live logs\n0) Back\n'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1) action='status'; systemctl status "$unit" --no-pager || true; pause ;;
      2) action='start'; if systemctl start "$unit"; then printf '%sService started.%s\n' "$GREEN" "$RESET"; else fail 'Could not start the service.'; fi; printf 'Command: sudo systemctl %s %s\n' "$action" "$unit"; pause ;;
      3) action='stop'; if systemctl stop "$unit"; then printf '%sService stopped.%s\n' "$GREEN" "$RESET"; else fail 'Could not stop the service.'; fi; printf 'Command: sudo systemctl %s %s\n' "$action" "$unit"; pause ;;
      4) action='restart'; if systemctl restart "$unit"; then printf '%sService restarted.%s\n' "$GREEN" "$RESET"; else fail 'Could not restart the service.'; fi; printf 'Command: sudo systemctl %s %s\n' "$action" "$unit"; pause ;;
      5) if systemctl enable "$unit"; then printf '%sAutomatic start enabled.%s\n' "$GREEN" "$RESET"; else fail 'Could not enable automatic start.'; fi; printf 'Command: sudo systemctl enable %s\n' "$unit"; pause ;;
      6) if systemctl disable "$unit"; then printf '%sAutomatic start disabled.%s\n' "$GREEN" "$RESET"; else fail 'Could not disable automatic start.'; fi; printf 'Command: sudo systemctl disable %s\n' "$unit"; pause ;;
      7) journalctl -u "$unit" -n 100 --no-pager || true; pause ;;
      8) printf 'Press Ctrl+C to return to the menu.\n'; journalctl -u "$unit" -f || true; pause ;;
      0) return ;;
      *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"; sleep 1 ;;
    esac
  done
}

read_config_value() {
  local key="$1" file="$2"
  [[ -r "$file" ]] || return 0
  sed -n "s/^$key=//p" "$file" | head -n 1
}

reconfigure_anytls() {
  local current_listen current_ip current_port password encoded tmp_config confirmation
  if ! unit_installed "$ANYTLS_UNIT" || [[ ! -f "$ANYTLS_CONFIG" ]]; then
    printf '%sAnyTLS server is not installed on this machine.%s\n' "$YELLOW" "$RESET"
    pause
    return
  fi

  current_listen="$(read_config_value ANYTLS_LISTEN "$ANYTLS_CONFIG")"
  read -r current_ip current_port < <(python3 - "$current_listen" <<'PY'
import sys
value = sys.argv[1]
if value.startswith("["):
    end = value.index("]")
    print(value[1:end], value[end + 2:])
else:
    print(*value.rsplit(":", 1))
PY
)

  header
  printf 'Reconfigure AnyTLS server\nThe service will restart after saving the new settings.\n\n'
  read_valid 'Listen IP' "$current_ip" valid_ip SERVER_IP
  read_valid 'Listen port' "$current_port" valid_port SERVER_PORT
  ask_password
  password="$REPLY"
  encoded="$(printf '%s' "$password" | base64 | tr -d '\n')"
  unset password REPLY
  if [[ "$SERVER_IP" == *:* ]]; then
    SERVER_LISTEN="[$SERVER_IP]:$SERVER_PORT"
  else
    SERVER_LISTEN="$SERVER_IP:$SERVER_PORT"
  fi

  printf '\nListen address: %s\n' "$SERVER_LISTEN"
  read -r -p 'Type yes to save and restart AnyTLS: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Cancelled. No settings were changed.\n'
    pause
    return
  fi

  tmp_config="$TMP_DIR/anytls.env"
  printf 'ANYTLS_LISTEN=%s\nANYTLS_PASSWORD_B64=%s\n' "$SERVER_LISTEN" "$encoded" > "$tmp_config"
  install -o root -g root -m 0600 "$tmp_config" "$ANYTLS_CONFIG.new"
  mv -f -- "$ANYTLS_CONFIG.new" "$ANYTLS_CONFIG"
  unset encoded
  if systemctl restart "$ANYTLS_UNIT"; then
    printf '%sAnyTLS settings saved and service restarted.%s\n' "$GREEN" "$RESET"
  else
    fail 'Settings were saved, but AnyTLS did not restart. Review the service logs.'
    systemctl status "$ANYTLS_UNIT" --no-pager || true
    journalctl -u "$ANYTLS_UNIT" -n 30 --no-pager || true
  fi
  pause
}

anytls_menu() {
  local choice
  while true; do
    header
    printf 'AnyTLS server\n\n1) Manage service\n2) Reconfigure listen IP, port, and password\n0) Back\n'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1)
        if unit_installed "$ANYTLS_UNIT"; then
          unit_menu "$ANYTLS_UNIT" 'AnyTLS server'
        else
          printf '%sAnyTLS server is not installed on this machine.%s\n' "$YELLOW" "$RESET"
          pause
        fi
        ;;
      2) reconfigure_anytls ;;
      0) return ;;
      *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"; sleep 1 ;;
    esac
  done
}

ensure_tunnel_user() {
  if ! getent passwd "$TUNNEL_USER" >/dev/null 2>&1; then
    local nologin
    nologin="$(command -v nologin || true)"
    if [[ -z "$nologin" && -x /usr/sbin/nologin ]]; then nologin='/usr/sbin/nologin'; fi
    if [[ -z "$nologin" && -x /sbin/nologin ]]; then nologin='/sbin/nologin'; fi
    if [[ -z "$nologin" ]]; then nologin='/bin/false'; fi
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell "$nologin" "$TUNNEL_USER"
  fi
  [[ "$(id -u "$TUNNEL_USER")" != '0' ]] || { fail 'The forwarding account has UID 0.'; return 1; }
  TUNNEL_GROUP="$(id -gn "$TUNNEL_USER")"
  install -d -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0700 "$TUNNEL_DIR"
}

install_latest_gost() {
  local machine_arch arch release_file archive stage
  local -a release_info
  command -v curl >/dev/null 2>&1 || { fail 'curl is required to download GOST.'; return 1; }
  command -v python3 >/dev/null 2>&1 || { fail 'python3 is required to validate the GOST release.'; return 1; }

  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64|amd64) arch='amd64' ;;
    aarch64|arm64) arch='arm64' ;;
    *) fail "GOST release architecture is not supported: $machine_arch (supported: amd64 and arm64)."; return 1 ;;
  esac

  release_file="$TMP_DIR/gost-release.json"
  if ! curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 60 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --user-agent 'anytls-go-installer' "$GOST_API" --output "$release_file"; then
    fail 'Could not fetch the latest stable GOST release from GitHub.'
    return 1
  fi

  mapfile -t release_info < <(python3 - "$release_file" "$arch" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    release = json.load(stream)
tag = release.get("tag_name", "")
if not tag or release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub did not return a stable GOST release.")
version = tag[1:] if tag.startswith("v") else tag
if not re.fullmatch(r"[0-9A-Za-z._-]+", version):
    raise SystemExit("The GOST release version is invalid.")
name = f"gost_{version}_linux_{sys.argv[2]}.tar.gz"
matches = [asset for asset in release.get("assets", []) if asset.get("name") == name]
if len(matches) != 1:
    raise SystemExit(f"Official GOST release archive not found: {name}")
asset = matches[0]
url = asset.get("browser_download_url", "")
if not url.startswith("https://github.com/go-gost/gost/releases/download/"):
    raise SystemExit("The GOST download URL is unexpected.")
digest = asset.get("digest", "")
if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("GitHub did not provide a valid SHA-256 digest for the GOST archive.")
print(tag)
print(url)
print(digest.split(":", 1)[1])
PY
)
  if (( ${#release_info[@]} != 3 )); then
    fail 'Could not validate GOST release metadata or its SHA-256 digest.'
    return 1
  fi

  printf 'Downloading official GOST %s for Linux/%s...\n' "${release_info[0]}" "$arch"
  archive="$TMP_DIR/gost.tar.gz"
  if ! curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 300 \
    --user-agent 'anytls-go-installer' "${release_info[1]}" --output "$archive"; then
    fail 'Could not download the GOST release archive.'
    return 1
  fi
  stage="$TMP_DIR/anytls-gost"
  if ! python3 - "$archive" "${release_info[2]}" "$stage" <<'PY'
import hashlib
import os
import sys
import tarfile

archive_path, expected_digest, output_path = sys.argv[1:]
digest = hashlib.sha256()
with open(archive_path, "rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest().lower() != expected_digest.lower():
    raise SystemExit("The GOST archive SHA-256 does not match GitHub's release digest.")
try:
    with tarfile.open(archive_path, "r:gz") as package:
        candidates = [member for member in package.getmembers()
                      if member.name.rsplit("/", 1)[-1] == "gost" and member.isfile()]
        if len(candidates) != 1:
            raise SystemExit("The archive did not contain exactly one regular gost executable.")
        source = package.extractfile(candidates[0])
        if source is None:
            raise SystemExit("Could not read the GOST executable from the archive.")
        with source, open(output_path, "wb") as target:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                target.write(chunk)
except (OSError, tarfile.TarError) as error:
    raise SystemExit(f"The GOST archive is invalid: {error}")
if os.path.getsize(output_path) == 0:
    raise SystemExit("The downloaded GOST executable is empty.")
os.chmod(output_path, 0o755)
PY
  then
    fail 'GOST archive validation failed; installation stopped.'
    return 1
  fi
  install -o root -g root -m 0755 "$stage" "$GOST_BIN.new"
  mv -f -- "$GOST_BIN.new" "$GOST_BIN"
}

setup_forward() {
  local dest_host dest_port local_bind confirmation local_display dest_display
  local env_tmp service_tmp wrapper_tmp work_dir
  if ! command -v python3 >/dev/null 2>&1; then
    fail 'python3 is required for input validation.'
    pause
    return 1
  fi

  header
  printf '%sDirect Iran-to-abroad TCP forwarding with GOST%s\n\n' "$GREEN" "$RESET"
  printf 'This Iran server accepts the AnyTLS TCP connection and forwards it directly to the AnyTLS server abroad.\n'
  printf 'The incoming and destination ports are kept identical, so clients only replace the server IP in their AnyTLS profile.\n\n'
  read_valid 'Foreign AnyTLS server address (IP or DNS name)' '' valid_host DEST_HOST
  read_valid 'AnyTLS TCP port (also used as the Iran entry port)' '443' valid_port DEST_PORT
  read_valid 'Listen IP on this Iran server (0.0.0.0 accepts IPv4 connections on all interfaces)' '0.0.0.0' valid_ip LOCAL_BIND

  if [[ "$LOCAL_BIND" == *:* ]]; then local_display="[$LOCAL_BIND]:$DEST_PORT"; else local_display="$LOCAL_BIND:$DEST_PORT"; fi
  if [[ "$DEST_HOST" == *:* ]]; then dest_display="[$DEST_HOST]:$DEST_PORT"; else dest_display="$DEST_HOST:$DEST_PORT"; fi

  header
  printf 'Forwarding summary\n\n'
  printf 'Iran listener:            %s\n' "$local_display"
  printf 'Foreign AnyTLS target:    %s\n' "$dest_display"
  printf 'Client profile:           replace only the server IP with the Iran server public IP\n'
  printf 'AnyTLS port and password: unchanged\n\n'
  printf 'Confirm the destination address and port are reachable from this Iran server. Allow inbound TCP on this port in both the server firewall and the hosting provider firewall.\n'
  read -r -p 'Type yes to install GOST and enable the forwarding service: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Cancelled. No forwarding service was changed.\n'
    pause
    return 1
  fi

  install_latest_gost || { pause; return 1; }
  ensure_tunnel_user || { pause; return 1; }
  work_dir="$(mktemp -d -p "$TMP_DIR" forward.XXXXXXXX)"
  chmod 0700 "$work_dir"
  env_tmp="$work_dir/forward.env"
  printf 'LOCAL_BIND=%s\nLOCAL_PORT=%s\nDEST_HOST=%s\nDEST_PORT=%s\n' \
    "$LOCAL_BIND" "$DEST_PORT" "$DEST_HOST" "$DEST_PORT" > "$env_tmp"
  install -o root -g root -m 0600 "$env_tmp" "$TUNNEL_CONFIG.new"

  wrapper_tmp="$work_dir/anytls-forward-start"
  cat > "$wrapper_tmp" <<'WRAPPER'
#!/bin/sh
set -eu
bind_host="$LOCAL_BIND"
destination_host="$DEST_HOST"
case "$bind_host" in *:*) bind_host="[$bind_host]" ;; esac
case "$destination_host" in *:*) destination_host="[$destination_host]" ;; esac
exec /usr/local/bin/anytls-gost -L "tcp://${bind_host}:${LOCAL_PORT}/${destination_host}:${DEST_PORT}"
WRAPPER
  chmod 0755 "$wrapper_tmp"

  service_tmp="$work_dir/anytls-tunnel.service"
  cat > "$service_tmp" <<'UNIT'
[Unit]
Description=Direct AnyTLS TCP forwarding to the foreign server (GOST)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=anytls-tunnel
EnvironmentFile=/etc/anytls-tunnel/forward.env
ExecStart=/usr/local/libexec/anytls-tunnel-start
Restart=always
RestartSec=5s
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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

  if systemctl is-active --quiet "$TUNNEL_UNIT"; then
    if ! systemctl stop "$TUNNEL_UNIT"; then
      fail 'Could not stop the existing forwarding service; its files were left unchanged.'
      pause
      return 1
    fi
  fi
  mv -f -- "$TUNNEL_CONFIG.new" "$TUNNEL_CONFIG"
  install -d -o root -g root -m 0755 /usr/local/libexec
  install -o root -g root -m 0755 "$wrapper_tmp" "$TUNNEL_WRAPPER.new"
  mv -f -- "$TUNNEL_WRAPPER.new" "$TUNNEL_WRAPPER"
  install -o root -g root -m 0644 "$service_tmp" "$TUNNEL_SERVICE_FILE.new"
  mv -f -- "$TUNNEL_SERVICE_FILE.new" "$TUNNEL_SERVICE_FILE"

  systemctl daemon-reload
  if ! systemctl enable --now "$TUNNEL_UNIT"; then
    fail 'The forwarding service was saved, but could not start. Check whether the selected port is already in use and review the service logs.'
    systemctl status "$TUNNEL_UNIT" --no-pager || true
    journalctl -u "$TUNNEL_UNIT" -n 40 --no-pager || true
    pause
    return 1
  fi

  header
  printf '%sDirect TCP forwarding is active.%s\n\n' "$GREEN" "$RESET"
  printf 'Client server address: Iran server public IP\nClient port:           %s\n' "$DEST_PORT"
  printf 'Client password:       the same AnyTLS password configured abroad\n\n'
  printf 'Allow inbound TCP port %s in the Iran server firewall and hosting provider firewall.\n' "$DEST_PORT"
  printf 'Manage the service from this panel or with: sudo systemctl status %s\n' "$TUNNEL_UNIT"
  pause
}

tunnel_menu() {
  local choice
  while true; do
    header
    printf 'Direct Iran-to-abroad TCP forwarding (GOST)\n\n'
    printf 'Service status: %s\n' "$(forward_state)"
    if [[ -r "$TUNNEL_CONFIG" ]] && grep -q '^SSH_HOST=' "$TUNNEL_CONFIG"; then
      printf '\n%sA previous SSH setup was found. Choose option 1 to replace it with direct GOST forwarding.%s\n' "$YELLOW" "$RESET"
    fi
    printf '\n1) Set up or update direct forwarding\n2) Manage forwarding service\n3) Show forwarding configuration\n0) Back\n'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1) setup_forward || true ;;
      2)
        if unit_installed "$TUNNEL_UNIT"; then
          unit_menu "$TUNNEL_UNIT" 'Forwarding service'
        else
          printf '%sForwarding is not configured yet.%s\n' "$YELLOW" "$RESET"
          pause
        fi
        ;;
      3)
        if [[ -r "$TUNNEL_CONFIG" ]]; then
          printf '\n'
          cat "$TUNNEL_CONFIG"
        else
          printf '%sNo forwarding configuration found.%s\n' "$YELLOW" "$RESET"
        fi
        pause
        ;;
      0) return ;;
      *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"; sleep 1 ;;
    esac
  done
}

command_reference() {
  header
  printf 'AnyTLS server commands:\n'
  printf '  systemctl status anytls\n  systemctl start anytls\n  systemctl stop anytls\n  systemctl restart anytls\n  systemctl enable anytls\n  systemctl disable anytls\n  journalctl -u anytls -f\n\n'
  printf 'Direct GOST TCP forwarding commands:\n'
  printf '  systemctl status anytls-tunnel\n  systemctl start anytls-tunnel\n  systemctl stop anytls-tunnel\n  systemctl restart anytls-tunnel\n  systemctl enable anytls-tunnel\n  systemctl disable anytls-tunnel\n  journalctl -u anytls-tunnel -f\n\n'
  printf 'Installer/update command:\n'
  printf '  installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"\n'
  pause
}

main_menu() {
  local choice
  while true; do
    header
    printf 'AnyTLS server: %s\n' "$(unit_state "$ANYTLS_UNIT")"
    printf 'GOST forward:  %s\n\n' "$(forward_state)"
    printf '1) AnyTLS server management\n2) Direct Iran-to-abroad TCP forwarding management (GOST)\n3) Show command reference\n0) Exit\n'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1) anytls_menu ;;
      2) tunnel_menu ;;
      3) command_reference ;;
      0) return ;;
      *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"; sleep 1 ;;
    esac
  done
}

require_root "$@"
if [[ ! -d /run/systemd/system ]]; then
  fail 'systemd is not active. This panel requires systemd.'
  exit 1
fi
TMP_DIR="$(mktemp -d -t anytls-panel.XXXXXXXX)"
chmod 0700 "$TMP_DIR"

if [[ "$#" -gt 0 && "$1" == '--setup-forward' ]]; then
  shift
  setup_forward || true
fi
main_menu
