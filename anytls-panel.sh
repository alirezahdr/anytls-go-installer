#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export LC_ALL=C

readonly ANYTLS_UNIT='anytls'
readonly ANYTLS_CONFIG='/etc/anytls/anytls.env'
readonly CLIENT_CONFIG_HELPER='/usr/local/bin/anytls-client-config.py'
readonly CLIENT_DIR='/root/anytls-clients'
readonly INSTALLER_FILE='/usr/local/libexec/anytls-installer'
readonly TUNNEL_UNIT='anytls-tunnel'
readonly TUNNEL_USER='anytls-tunnel'
readonly TUNNEL_DIR='/etc/anytls-tunnel'
readonly TUNNEL_CONFIG='/etc/anytls-tunnel/forward.env'
readonly TUNNEL_WRAPPER='/usr/local/libexec/anytls-tunnel-start'
readonly TUNNEL_SERVICE_FILE='/etc/systemd/system/anytls-tunnel.service'
readonly GOST_CONFIG='/etc/anytls-tunnel/gost.json'
readonly GOST_API='https://api.github.com/repos/go-gost/gost/releases/latest'
readonly GOST_BIN='/usr/local/bin/anytls-gost'

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
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

menu_item() {
  printf '%s%s)%s %s\n' "$CYAN" "$1" "$RESET" "$2"
}

color_status() {
  case "$1" in
    active|enabled) printf '%s%s%s' "$GREEN" "$1" "$RESET" ;;
    inactive|disabled|not\ installed) printf '%s%s%s' "$YELLOW" "$1" "$RESET" ;;
    *) printf '%s%s%s' "$RED" "$1" "$RESET" ;;
  esac
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
    menu_item 1 'Status'
    menu_item 2 'Start'
    menu_item 3 'Stop'
    menu_item 4 'Restart'
    menu_item 5 'Enable at boot'
    menu_item 6 'Disable at boot'
    menu_item 7 'Recent logs'
    menu_item 8 'Follow live logs'
    menu_item 0 'Back'
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
  local current_listen current_ip current_port encoded new_password tmp_config backup_config confirmation
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
  printf 'Reconfigure AnyTLS-Go server\nA new random password will be generated and saved with the listen address. Existing client profiles will stop working.\n\n'
  read_valid 'Listen IP' "$current_ip" valid_ip SERVER_IP
  read_valid 'Listen port' "$current_port" valid_port SERVER_PORT
  if [[ "$SERVER_IP" == *:* ]]; then
    SERVER_LISTEN="[$SERVER_IP]:$SERVER_PORT"
  else
    SERVER_LISTEN="$SERVER_IP:$SERVER_PORT"
  fi

  printf '\nListen address: %s\n' "$SERVER_LISTEN"
  read -r -p 'Type yes to save, generate a new password, and restart AnyTLS: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Cancelled. No settings were changed.\n'
    pause
    return
  fi

  new_password="$(python3 -c 'import secrets; print(secrets.token_hex(16))')" || {
    fail 'Could not generate a new password; no settings were changed.'
    pause
    return
  }
  if [[ ! "$new_password" =~ ^[0-9a-f]{32}$ ]]; then
    unset new_password
    fail 'Password generation returned an invalid value; no settings were changed.'
    pause
    return
  fi
  encoded="$(printf '%s' "$new_password" | base64 | tr -d '\n')"
  tmp_config="$TMP_DIR/anytls.env"
  backup_config="$TMP_DIR/anytls.env.previous"
  if ! cp -- "$ANYTLS_CONFIG" "$backup_config"; then
    unset new_password encoded
    fail 'Could not back up the current settings; no settings were changed.'
    pause
    return
  fi
  if ! printf 'ANYTLS_LISTEN=%s\nANYTLS_PASSWORD_B64=%s\n' "$SERVER_LISTEN" "$encoded" > "$tmp_config" ||
    ! install -o root -g root -m 0600 "$tmp_config" "$ANYTLS_CONFIG.new" ||
    ! mv -f -- "$ANYTLS_CONFIG.new" "$ANYTLS_CONFIG"; then
    rm -f -- "$ANYTLS_CONFIG.new"
    unset new_password encoded
    fail 'Could not save the new settings; the existing settings were left unchanged.'
    pause
    return
  fi
  unset encoded
  if systemctl restart "$ANYTLS_UNIT" && systemctl is-active --quiet "$ANYTLS_UNIT"; then
    printf '%sAnyTLS settings saved and service restarted.%s\n' "$GREEN" "$RESET"
    printf '\nNew AnyTLS password (save it now): %s\n' "$new_password"
    printf 'Old client profiles no longer work. Export fresh QR/JSON profiles from option 3.\n'
    unset new_password
  else
    unset new_password
    fail 'AnyTLS did not start with the new settings. Restoring the previous settings.'
    if install -o root -g root -m 0600 "$backup_config" "$ANYTLS_CONFIG.rollback" && mv -f -- "$ANYTLS_CONFIG.rollback" "$ANYTLS_CONFIG"; then
      if systemctl restart "$ANYTLS_UNIT" && systemctl is-active --quiet "$ANYTLS_UNIT"; then
        printf '%sPrevious AnyTLS settings were restored and the service is active.%s\n' "$GREEN" "$RESET"
      else
        fail 'Previous settings were restored, but the service still did not start.'
      fi
    else
      fail 'Could not restore the previous settings automatically.'
    fi
    systemctl status "$ANYTLS_UNIT" --no-pager || true
    journalctl -u "$ANYTLS_UNIT" -n 30 --no-pager || true
  fi
  pause
}

client_export_menu() {
  local germany_ip iran_ip direct_port tunnel_port sni default_port direct_text tunnel_text show_choice
  local -a direct_info tunnel_info
  if ! unit_installed "$ANYTLS_UNIT" || [[ ! -f "$ANYTLS_CONFIG" ]]; then
    printf '%sInstall the AnyTLS-Go server before exporting client profiles.%s\n' "$YELLOW" "$RESET"
    pause
    return
  fi
  if [[ "$(read_config_value ANYTLS_BACKEND "$ANYTLS_CONFIG")" == 'sing-box' ]]; then
    fail 'The server is still using sing-box. Choose Restore AnyTLS-Go single-user mode in the AnyTLS server menu first.'
    pause
    return
  fi
  if [[ ! -x "$CLIENT_CONFIG_HELPER" ]]; then
    fail 'The client profile component is missing. Run the quick installer again to update the panel files.'
    pause
    return
  fi
  default_port="$(python3 - "$ANYTLS_CONFIG" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^ANYTLS_LISTEN=(.*)$", text, re.M)
value = match.group(1) if match else ""
print(value.rsplit(":", 1)[-1].rstrip("]"))
PY
)"
  printf 'Create both AnyTLS-Go profiles using this server’s saved password:\n'
  printf '  Germany direct: clients connect to the Germany server without GOST.\n'
  printf '  Iran GOST tunnel: clients connect to Iran and GOST forwards to this Germany server.\n\n'
  read_valid 'Germany public IP or DNS name (direct profile)' '' valid_host germany_ip
  read_valid 'Iran public IP or DNS name (GOST tunnel profile)' '' valid_host iran_ip
  direct_port="$default_port"
  printf 'Germany AnyTLS-Go listening port: %s\n' "$direct_port"
  read_valid 'Iran GOST client-entry port (must match the Agent setup)' "$direct_port" valid_port tunnel_port
  read -r -p 'TLS server name/SNI [www.cloudflare.com]: ' sni
  sni="${sni:-www.cloudflare.com}"
  if ! direct_text="$("$CLIENT_CONFIG_HELPER" export --variant germany-direct --server "$germany_ip" --port "$direct_port" --sni "$sni")"; then
    fail 'Could not export the Germany direct profiles.'
    pause
    return
  fi
  mapfile -t direct_info <<< "$direct_text"
  (( ${#direct_info[@]} == 5 )) || { fail 'The direct profile exporter returned incomplete information.'; pause; return; }
  if ! tunnel_text="$("$CLIENT_CONFIG_HELPER" export --variant iran-gost-tunnel --server "$iran_ip" --port "$tunnel_port" --sni "$sni")"; then
    fail 'Could not export the Iran GOST tunnel profiles.'
    pause
    return
  fi
  mapfile -t tunnel_info <<< "$tunnel_text"
  (( ${#tunnel_info[@]} == 5 )) || { fail 'The tunnel profile exporter returned incomplete information.'; pause; return; }
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t PNG -s 6 -o "${tunnel_info[4]}" "${tunnel_info[0]}" || fail 'Iran tunnel JSON files were created, but its QR image could not be generated.'
    qrencode -t PNG -s 6 -o "${direct_info[4]}" "${direct_info[0]}" || fail 'Germany direct JSON files were created, but its QR image could not be generated.'
  else
    printf '\n%sqrencode is unavailable; JSON files were created without QR images.%s\n' "$YELLOW" "$RESET"
  fi
  printf '\n%sIran GOST tunnel — Server %s:%s%s\n' "$CYAN" "$iran_ip" "$tunnel_port" "$RESET"
  printf 'QR image:   %s\nAndroid:    %s\niOS:        %s\nWindows:    %s\n' \
    "${tunnel_info[4]}" "${tunnel_info[1]}" "${tunnel_info[2]}" "${tunnel_info[3]}"
  printf '\n%sGermany direct — Server %s:%s%s\n' "$CYAN" "$germany_ip" "$direct_port" "$RESET"
  printf 'QR image:   %s\nAndroid:    %s\niOS:        %s\nWindows:    %s\n' \
    "${direct_info[4]}" "${direct_info[1]}" "${direct_info[2]}" "${direct_info[3]}"
  printf '\nThe QR/link and JSON files use the profile name AnyTLS-Go. The tunnel port must equal the client-entry port exposed by GOST on Iran. These files contain the AnyTLS password; treat them as login credentials. NekoBox URL tests may still show a DNS/default-interface warning even when the proxy works.\n'
  printf '\nSelect what to print in this terminal for copying or scanning:\n'
  menu_item 1 'Show Iran GOST tunnel QR'
  menu_item 2 'Show Germany direct QR'
  menu_item 3 'Show Iran tunnel Android JSON'
  menu_item 4 'Show Germany direct Android JSON'
  menu_item 5 'Show Iran tunnel iOS JSON'
  menu_item 6 'Show Germany direct iOS JSON'
  menu_item 7 'Show Iran tunnel Windows JSON'
  menu_item 8 'Show Germany direct Windows JSON'
  menu_item 0 'Skip'
  while true; do
    read -r -p 'Select an option: ' show_choice
    case "$show_choice" in
      0|1|2|3|4|5|6|7|8) break ;;
      *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET" ;;
    esac
  done
  case "$show_choice" in
    1)
      header
      printf 'Iran GOST tunnel — scan this AnyTLS-Go QR in NekoBox:\n\n'
      if command -v qrencode >/dev/null 2>&1; then qrencode -t ANSIUTF8 "${tunnel_info[0]}"; else fail 'qrencode is not installed; use the PNG path or install qrencode.'; fi
      ;;
    2)
      header
      printf 'Germany direct — scan this AnyTLS-Go QR in NekoBox:\n\n'
      if command -v qrencode >/dev/null 2>&1; then qrencode -t ANSIUTF8 "${direct_info[0]}"; else fail 'qrencode is not installed; use the PNG path or install qrencode.'; fi
      ;;
    3) header; printf 'Iran GOST tunnel — Android sing-box JSON:\n\n'; cat "${tunnel_info[1]}" ;;
    4) header; printf 'Germany direct — Android sing-box JSON:\n\n'; cat "${direct_info[1]}" ;;
    5) header; printf 'Iran GOST tunnel — iOS sing-box JSON:\n\n'; cat "${tunnel_info[2]}" ;;
    6) header; printf 'Germany direct — iOS sing-box JSON:\n\n'; cat "${direct_info[2]}" ;;
    7) header; printf 'Iran GOST tunnel — Windows sing-box JSON:\n\n'; cat "${tunnel_info[3]}" ;;
    8) header; printf 'Germany direct — Windows sing-box JSON:\n\n'; cat "${direct_info[3]}" ;;
    0) ;;
  esac
  unset direct_text tunnel_text direct_info tunnel_info
  pause
}

anytls_menu() {
  local choice backend
  while true; do
    header
    backend="$(read_config_value ANYTLS_BACKEND "$ANYTLS_CONFIG")"
    printf '%sAnyTLS server (%s backend)%s\n\n' "$GREEN" "${backend:-AnyTLS-Go}" "$RESET"
    if unit_installed "$ANYTLS_UNIT"; then
      menu_item 1 'Manage service'
      if [[ "$backend" == 'sing-box' ]]; then
        menu_item 2 'Restore AnyTLS-Go single-user mode'
      else
        menu_item 2 'Reconfigure IP/port and generate a new password'
        menu_item 3 'Export AnyTLS-Go client QR and JSON'
      fi
    else
      printf '%sAnyTLS server is not installed on this machine.%s\n\n' "$YELLOW" "$RESET"
      menu_item 1 'Install AnyTLS server'
    fi
    menu_item 0 'Back'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1)
        if unit_installed "$ANYTLS_UNIT"; then
          unit_menu "$ANYTLS_UNIT" 'AnyTLS server'
        elif [[ -x "$INSTALLER_FILE" ]]; then
          "$INSTALLER_FILE" --install-anytls --no-panel || true
        else
          fail 'The installer component is missing. Run the quick install command again to update this panel.'
          pause
        fi
        ;;
      2)
        if unit_installed "$ANYTLS_UNIT"; then
          if [[ "$backend" == 'sing-box' ]]; then
            header
            printf '%sThis restores the single-password AnyTLS-Go server.%s\n' "$YELLOW" "$RESET"
            printf 'The first active account password will be retained. Existing sing-box files and client exports will be backed up.\n\n'
            "$INSTALLER_FILE" --restore-anytls-go --no-panel || true
            pause
          else
            reconfigure_anytls
          fi
        else
          printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"
          sleep 1
        fi
        ;;
      3)
        if unit_installed "$ANYTLS_UNIT" && [[ "$backend" != 'sing-box' ]]; then
          client_export_menu
        else
          printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"
          sleep 1
        fi
        ;;
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
  install -d -o root -g "$TUNNEL_GROUP" -m 0750 "$TUNNEL_DIR"
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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
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
  rm -f -- "$GOST_CONFIG"
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
  printf 'This setup replaces any existing direct or reverse GOST mode on this server.\n'
  printf 'Manage the service from this panel or with: sudo systemctl status %s\n' "$TUNNEL_UNIT"
  pause
}

write_reverse_relay_config() {
  local output_file="$1" bind_ip="$2" bind_port="$3" relay_user="$4" relay_password="$5"
  python3 - "$output_file" "$bind_ip" "$bind_port" "$relay_user" "$relay_password" <<'PY'
import ipaddress
import json
import sys

path, bind_ip, bind_port, username, password = sys.argv[1:]
try:
    ipaddress.ip_address(bind_ip)
except ValueError as error:
    raise SystemExit(f"Invalid relay bind IP: {error}")
host = f"[{bind_ip}]" if ":" in bind_ip else bind_ip
config = {
    "services": [{
        "name": "anytls-reverse-relay",
        "addr": f"{host}:{bind_port}",
        "handler": {
            "type": "relay",
            "auth": {"username": username, "password": password},
            "metadata": {"bind": True},
        },
        "listener": {"type": "tls"},
    }]
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2)
    stream.write("\n")
PY
}

write_reverse_agent_config() {
  local output_file="$1" relay_host="$2" relay_port="$3" entry_port="$4" target_host="$5" target_port="$6" relay_user="$7" relay_password="$8"
  python3 - "$output_file" "$relay_host" "$relay_port" "$entry_port" "$target_host" "$target_port" "$relay_user" "$relay_password" <<'PY'
import ipaddress
import json
import re
import sys

path, relay_host, relay_port, entry_port, target_host, target_port, username, password = sys.argv[1:]
try:
    ipaddress.ip_address(relay_host)
except ValueError:
    label = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    if len(relay_host) > 253 or not re.fullmatch(label + r"(?:\." + label + r")*\.?", relay_host):
        raise SystemExit("Invalid relay host")
relay_addr_host = f"[{relay_host}]" if ":" in relay_host else relay_host
try:
    ipaddress.ip_address(target_host)
except ValueError:
    label = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    if len(target_host) > 253 or not re.fullmatch(label + r"(?:\." + label + r")*\.?", target_host):
        raise SystemExit("Invalid target host")
target_addr_host = f"[{target_host}]" if ":" in target_host else target_host
config = {
    "services": [{
        "name": "anytls-reverse-agent",
        "addr": f":{entry_port}",
        "handler": {"type": "rtcp"},
        "listener": {"type": "rtcp", "chain": "chain-0"},
        "forwarder": {
            "nodes": [{"name": "anytls-backend", "addr": f"{target_addr_host}:{target_port}"}]
        },
    }],
    "chains": [{
        "name": "chain-0",
        "hops": [{
            "name": "hop-0",
            "nodes": [{
                "name": "relay-server",
                "addr": f"{relay_addr_host}:{relay_port}",
                "connector": {
                    "type": "relay",
                    "auth": {"username": username, "password": password},
                },
                "dialer": {"type": "tls", "tls": {"secure": False}},
            }],
        }],
    }],
}
with open(path, "w", encoding="utf-8") as stream:
    json.dump(config, stream, indent=2)
    stream.write("\n")
PY
}

install_reverse_service() {
  local work_dir="$1" mode="$2" description="$3" env_tmp wrapper_tmp service_tmp
  env_tmp="$work_dir/forward.env"
  wrapper_tmp="$work_dir/anytls-tunnel-start"
  service_tmp="$work_dir/anytls-tunnel.service"

  ensure_tunnel_user || return 1
  install_latest_gost || return 1

  cat > "$wrapper_tmp" <<'WRAPPER'
#!/bin/sh
set -eu
exec /usr/local/bin/anytls-gost -C /etc/anytls-tunnel/gost.json
WRAPPER
  chmod 0755 "$wrapper_tmp"
  cat > "$service_tmp" <<UNIT
[Unit]
Description=$description (GOST)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=anytls-tunnel
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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT

  if systemctl is-active --quiet "$TUNNEL_UNIT"; then
    if ! systemctl stop "$TUNNEL_UNIT"; then
      fail 'Could not stop the current GOST service; its active configuration was not replaced.'
      return 1
    fi
  fi

  install -o root -g "$TUNNEL_GROUP" -m 0640 "$work_dir/gost.json" "$GOST_CONFIG.new"
  printf 'TUNNEL_MODE=%s\n' "$mode" > "$env_tmp"
  case "$mode" in
    reverse-relay)
      printf 'RELAY_LISTEN=%s\nRELAY_PORT=%s\n' "$RELAY_BIND" "$RELAY_PORT" >> "$env_tmp"
      ;;
    reverse-agent)
      printf 'RELAY_HOST=%s\nRELAY_PORT=%s\nENTRY_PORT=%s\nTARGET_HOST=%s\nTARGET_PORT=%s\n' \
        "$RELAY_HOST" "$RELAY_PORT" "$ENTRY_PORT" "$TARGET_HOST" "$TARGET_PORT" >> "$env_tmp"
      ;;
  esac
  install -o root -g root -m 0600 "$env_tmp" "$TUNNEL_CONFIG.new"
  mv -f -- "$GOST_CONFIG.new" "$GOST_CONFIG"
  mv -f -- "$TUNNEL_CONFIG.new" "$TUNNEL_CONFIG"
  install -d -o root -g root -m 0755 /usr/local/libexec
  install -o root -g root -m 0755 "$wrapper_tmp" "$TUNNEL_WRAPPER.new"
  mv -f -- "$TUNNEL_WRAPPER.new" "$TUNNEL_WRAPPER"
  install -o root -g root -m 0644 "$service_tmp" "$TUNNEL_SERVICE_FILE.new"
  mv -f -- "$TUNNEL_SERVICE_FILE.new" "$TUNNEL_SERVICE_FILE"
  systemctl daemon-reload
  if ! systemctl enable --now "$TUNNEL_UNIT"; then
    fail 'The reverse GOST service was saved, but could not start. Review the service logs.'
    systemctl status "$TUNNEL_UNIT" --no-pager || true
    journalctl -u "$TUNNEL_UNIT" -n 40 --no-pager || true
    return 1
  fi
}

setup_reverse_relay() {
  local confirmation work_dir relay_user relay_password
  header
  printf '%sReverse GOST Relay setup — client-facing server%s\n\n' "$GREEN" "$RESET"
  printf 'Run this role on the server whose public IP clients should use. The AnyTLS-Go backend can run on another host; its Agent will create the client entry port here.\n'
  printf 'The Relay uses TLS and a generated credential. The Agent encrypts the connection but does not verify GOST’s automatically generated certificate.\n\n'
  read_valid 'Relay listen IP (0.0.0.0 accepts IPv4 connections on all interfaces)' '0.0.0.0' valid_ip RELAY_BIND
  read_valid 'Relay control port (allow this from the Agent server IP)' '8444' valid_port RELAY_PORT
  printf '\nThe Agent setup will separately choose the public client entry port on this Relay server.\n'
  read -r -p 'Type yes to install and enable the Relay service on this server: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Cancelled. No GOST service was changed.\n'
    pause
    return 1
  fi

  relay_user="anytls-$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
  relay_password="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
  work_dir="$(mktemp -d -p "$TMP_DIR" reverse-relay.XXXXXXXX)"
  chmod 0700 "$work_dir"
  write_reverse_relay_config "$work_dir/gost.json" "$RELAY_BIND" "$RELAY_PORT" "$relay_user" "$relay_password" || {
    unset relay_password
    fail 'Could not create the GOST relay configuration.'
    pause
    return 1
  }
  install_reverse_service "$work_dir" reverse-relay 'Reverse GOST Relay server' || {
    unset relay_password
    pause
    return 1
  }

  header
  printf '%sReverse GOST Relay is active on this server.%s\n\n' "$GREEN" "$RESET"
  printf 'Relay address:  use this server’s public IP and port %s\n' "$RELAY_PORT"
  printf 'Relay username: %s\n' "$relay_user"
  printf 'Relay password: %s\n\n' "$relay_password"
  printf 'Copy these credentials. On the server running AnyTLS-Go, choose GOST forwarding → reverse setup → Configure reverse Agent.\n'
  printf 'Allow TCP %s from the Agent server on this Relay host. Open the client entry port separately for client traffic.\n' "$RELAY_PORT"
  unset relay_password
  pause
}

setup_reverse_agent() {
  local confirmation relay_user relay_password work_dir
  header
  printf '%sReverse GOST Agent setup — AnyTLS backend server%s\n\n' "$GREEN" "$RESET"
  printf 'Run this role on the server that runs AnyTLS-Go. The Agent connects outbound to the Relay and forwards its public client entry port to the AnyTLS backend.\n\n'
  read_valid 'Relay server public IP or DNS name' '' valid_host RELAY_HOST
  read_valid 'Relay control port' '8444' valid_port RELAY_PORT
  read_valid 'Client entry port to expose on the Relay server' '8443' valid_port ENTRY_PORT
  while [[ "$ENTRY_PORT" == "$RELAY_PORT" ]]; do
    printf '%sThe client entry port must differ from the Relay control port.%s\n' "$YELLOW" "$RESET"
    read_valid 'Choose a different client entry port' '8443' valid_port ENTRY_PORT
  done
  read_valid 'AnyTLS backend IP or DNS name' '127.0.0.1' valid_host TARGET_HOST
  read_valid 'AnyTLS backend listening port' "$ENTRY_PORT" valid_port TARGET_PORT
  while true; do
    read -r -p 'Relay username (from the Relay setup): ' relay_user
    if [[ "$relay_user" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then break; fi
    printf '%sUse 1–64 letters, numbers, dots, underscores, or hyphens.%s\n' "$YELLOW" "$RESET"
  done
  while true; do
    read -r -s -p 'Relay password (input hidden): ' relay_password
    printf '\n'
    if [[ "$relay_password" =~ ^[A-Za-z0-9._-]{20,128}$ ]]; then break; fi
    printf '%sPassword must contain 20–128 letters, numbers, dots, underscores, or hyphens.%s\n' "$YELLOW" "$RESET"
  done
  printf '\nRelay server:         %s:%s\n' "$RELAY_HOST" "$RELAY_PORT"
  printf 'Client entry port:    %s on the Relay server\n' "$ENTRY_PORT"
  printf 'AnyTLS backend:       %s:%s\n' "$TARGET_HOST" "$TARGET_PORT"
  printf 'Client profile:       use the Relay server public IP and entry port %s; keep the AnyTLS password\n\n' "$ENTRY_PORT"
  printf 'TLS encrypts the Relay connection; the Agent does not verify GOST’s auto-generated certificate.\n'
  printf 'Open TCP %s on the Relay server to client networks and TCP %s from this Agent host to the Relay.\n' "$ENTRY_PORT" "$RELAY_PORT"
  read -r -p 'Type yes to install and enable the reverse agent: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    unset relay_password
    printf 'Cancelled. No GOST service was changed.\n'
    pause
    return 1
  fi

  work_dir="$(mktemp -d -p "$TMP_DIR" reverse-agent.XXXXXXXX)"
  chmod 0700 "$work_dir"
  write_reverse_agent_config "$work_dir/gost.json" "$RELAY_HOST" "$RELAY_PORT" "$ENTRY_PORT" "$TARGET_HOST" "$TARGET_PORT" "$relay_user" "$relay_password" || {
    unset relay_password
    fail 'Could not create the GOST reverse agent configuration.'
    pause
    return 1
  }
  unset relay_password
  install_reverse_service "$work_dir" reverse-agent 'Reverse GOST Agent on the AnyTLS backend server' || {
    pause
    return 1
  }

  header
  printf '%sReverse GOST agent is active.%s\n\n' "$GREEN" "$RESET"
  printf 'Client server address: Relay server public IP\nClient port:           %s\n' "$ENTRY_PORT"
  printf 'Client AnyTLS password: unchanged\n\n'
  printf 'Allow inbound TCP %s on the Relay server and provider firewall.\n' "$ENTRY_PORT"
  printf 'Manage this host’s agent with: sudo systemctl status %s\n' "$TUNNEL_UNIT"
  pause
}

setup_reverse() {
  local choice
  header
  printf '%sReverse TCP tunnel setup with GOST%s\n\n' "$GREEN" "$RESET"
  printf 'Configure the Relay on the client-facing server, then configure the Agent on the server running AnyTLS-Go. Both roles use the anytls-tunnel service name on their respective hosts.\n'
  printf 'For AnyTLS-Go on Germany with clients using the Iran IP: Relay on Iran, Agent on Germany.\n'
  printf 'Setting up a role replaces the existing GOST mode on that server.\n\n'
  menu_item 1 'Configure Relay server (client entry point)'
  menu_item 2 'Configure reverse Agent (AnyTLS backend)'
  menu_item 0 'Back'
  read -r -p 'Select a role: ' choice
  case "$choice" in
    1) setup_reverse_relay ;;
    2) setup_reverse_agent ;;
    0) return ;;
    *) printf '%sInvalid option.%s\n' "$YELLOW" "$RESET"; pause ;;
  esac
}

tunnel_menu() {
  local choice mode
  while true; do
    header
    printf 'GOST forwarding management\n\n'
    mode="$(read_config_value TUNNEL_MODE "$TUNNEL_CONFIG")"
    case "$mode" in
      reverse-relay) printf 'Configured role: reverse GOST Relay (client entry point)\n' ;;
      reverse-agent) printf 'Configured role: reverse GOST Agent (AnyTLS backend)\n' ;;
      *)
        if [[ -r "$TUNNEL_CONFIG" ]] && grep -q '^LOCAL_BIND=' "$TUNNEL_CONFIG"; then
          printf 'Configured mode: direct TCP forwarding\n'
        else
          printf 'Configured mode: not set\n'
        fi
        ;;
    esac
    printf 'Service status: %s\n' "$(color_status "$(forward_state)")"
    if [[ -r "$TUNNEL_CONFIG" ]] && grep -q '^SSH_HOST=' "$TUNNEL_CONFIG"; then
      printf '\n%sA previous SSH setup was found. Choose option 1 to replace it with direct GOST forwarding.%s\n' "$YELLOW" "$RESET"
    fi
    menu_item 1 'Set up or update direct forwarding'
    menu_item 2 'Set up or update reverse GOST tunnel'
    menu_item 3 'Manage forwarding service'
    menu_item 4 'Show forwarding configuration'
    menu_item 0 'Back'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1) setup_forward || true ;;
      2) setup_reverse || true ;;
      3)
        if unit_installed "$TUNNEL_UNIT"; then
          unit_menu "$TUNNEL_UNIT" 'Forwarding service'
        else
          printf '%sForwarding is not configured yet.%s\n' "$YELLOW" "$RESET"
          pause
        fi
        ;;
      4)
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
  printf 'GOST forwarding commands (direct or reverse):\n'
  printf '  systemctl status anytls-tunnel\n  systemctl start anytls-tunnel\n  systemctl stop anytls-tunnel\n  systemctl restart anytls-tunnel\n  systemctl enable anytls-tunnel\n  systemctl disable anytls-tunnel\n  journalctl -u anytls-tunnel -f\n\n'
  printf 'Installer/update command:\n'
  printf '  installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"\n'
  pause
}

main_menu() {
  local choice
  while true; do
    header
    printf 'AnyTLS server: %s\n' "$(color_status "$(unit_state "$ANYTLS_UNIT")")"
    printf 'GOST tunnel:   %s\n\n' "$(color_status "$(forward_state)")"
    menu_item 1 'AnyTLS server management'
    menu_item 2 'GOST forwarding management (direct or reverse)'
    menu_item 3 'Show command reference'
    menu_item 0 'Exit'
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
