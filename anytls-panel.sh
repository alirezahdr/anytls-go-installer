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
readonly TUNNEL_KEY='/etc/anytls-tunnel/id_ed25519'
readonly TUNNEL_KNOWN_HOSTS='/etc/anytls-tunnel/known_hosts'
readonly TUNNEL_WRAPPER='/usr/local/libexec/anytls-tunnel-start'
readonly TUNNEL_SERVICE_FILE='/etc/systemd/system/anytls-tunnel.service'

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

valid_user() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9._-]{0,31}$ ]]
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
  [[ "$(id -u "$TUNNEL_USER")" != '0' ]] || { fail 'The tunnel account has UID 0.'; return 1; }
  TUNNEL_GROUP="$(id -gn "$TUNNEL_USER")"
  install -d -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0700 "$TUNNEL_DIR"
}

host_for_forward() {
  if [[ "$1" == *:* ]]; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

setup_tunnel() {
  local command_name ssh_bin ssh_host ssh_port ssh_user local_bind local_port dest_host dest_port
  local key_tmp pub_tmp scan_tmp fingerprint confirmation forward_bind forward_dest
  local env_tmp service_tmp wrapper_tmp work_dir

  for command_name in ssh ssh-keygen ssh-keyscan; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      fail "Required OpenSSH client command not found: $command_name. Install the OpenSSH client package and try again."
      pause
      return 1
    fi
  done
  if ! command -v python3 >/dev/null 2>&1; then
    fail 'python3 is required for input validation.'
    pause
    return 1
  fi
  ssh_bin="$(command -v ssh)"
  [[ "$ssh_bin" =~ ^/[A-Za-z0-9._/-]+$ ]] || { fail 'The ssh executable path contains unsupported characters.'; pause; return 1; }

  header
  printf '%sIran-to-abroad TCP forwarding setup%s\n\n' "$GREEN" "$RESET"
  printf 'Clients connect to this server in Iran. This machine opens an SSH connection to the foreign server, then forwards TCP traffic to the AnyTLS host and port as seen from that foreign server.\n'
  printf 'The AnyTLS server must already be running at the destination. This wizard does not change the foreign server.\n\n'

  read_valid 'Foreign server SSH host (IP or DNS name)' '' valid_host SSH_HOST
  read_valid 'Foreign server SSH port' '22' valid_port SSH_PORT
  read_valid 'SSH username on the foreign server' '' valid_user SSH_USER
  read_valid 'Local listen IP on this Iran server (0.0.0.0 accepts clients on all IPv4 interfaces)' '0.0.0.0' valid_ip LOCAL_BIND
  read_valid 'Local TCP port for clients on this Iran server' '443' valid_port LOCAL_PORT
  read_valid 'AnyTLS destination host as seen from the foreign server' '127.0.0.1' valid_host DEST_HOST
  read_valid 'AnyTLS destination TCP port' '443' valid_port DEST_PORT

  header
  printf 'Forwarding summary\n\n'
  printf 'Iran server listener: %s:%s\n' "$LOCAL_BIND" "$LOCAL_PORT"
  printf 'SSH connection:      %s@%s:%s\n' "$SSH_USER" "$SSH_HOST" "$SSH_PORT"
  printf 'Foreign destination: %s:%s\n\n' "$DEST_HOST" "$DEST_PORT"
  printf 'On the foreign SSH server, the account must allow local TCP forwarding to this exact destination. Install the public key from the next step into that account authorized_keys file.\n'
  read -r -p 'Press Enter to create or reuse the dedicated SSH key... ' _

  ensure_tunnel_user || { pause; return 1; }
  work_dir="$(mktemp -d -p "$TMP_DIR" tunnel.XXXXXXXX)"
  chmod 0700 "$work_dir"
  key_tmp="$work_dir/id_ed25519"
  pub_tmp="$work_dir/id_ed25519.pub"

  if [[ -f "$TUNNEL_KEY" ]]; then
    if ! ssh-keygen -y -P '' -f "$TUNNEL_KEY" > "$pub_tmp"; then
      fail 'The existing tunnel key is invalid or encrypted. Move it aside and run setup again.'
      pause
      return 1
    fi
  else
    if ! ssh-keygen -q -t ed25519 -N '' -C "anytls-tunnel@$(hostname)" -f "$key_tmp"; then
      fail 'Could not create an SSH key.'
      pause
      return 1
    fi
    install -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0600 "$key_tmp" "$TUNNEL_KEY"
    install -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0644 "$pub_tmp" "$TUNNEL_KEY.pub"
  fi
  chown "$TUNNEL_USER:$TUNNEL_GROUP" "$TUNNEL_KEY"
  chmod 0600 "$TUNNEL_KEY"
  install -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0644 "$pub_tmp" "$TUNNEL_KEY.pub"

  scan_tmp="$work_dir/known_hosts"
  if ! ssh-keyscan -T 10 -p "$SSH_PORT" "$SSH_HOST" > "$scan_tmp" 2>/dev/null || [[ ! -s "$scan_tmp" ]]; then
    fail 'Could not retrieve the foreign server SSH host key. Check its address, port, and firewall.'
    pause
    return 1
  fi
  fingerprint="$(ssh-keygen -lf "$scan_tmp" 2>/dev/null || true)"
  if [[ -z "$fingerprint" ]]; then
    fail 'Could not calculate a fingerprint for the SSH host key. Tunnel setup stopped.'
    pause
    return 1
  fi
  header
  printf 'Verify the SSH host key fingerprint using the foreign server console or another trusted channel:\n\n%s\n\n' "$fingerprint"
  printf 'Only accept this key after verifying its fingerprint independently.\n'
  read -r -p 'Type yes to trust this host key: ' confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Cancelled. The host key was not saved and the tunnel was not configured.\n'
    pause
    return 1
  fi

  header
  printf 'Dedicated public key\n\n'
  cat "$TUNNEL_KEY.pub"
  printf '\nAdd this line to the authorized_keys file for %s on the verified foreign server.\n' "$SSH_USER"
  printf 'The remote sshd must permit local TCP forwarding to %s:%s.\n\n' "$DEST_HOST" "$DEST_PORT"
  read -r -p 'Press Enter after adding the key on the foreign server... ' _

  install -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" -m 0644 "$scan_tmp" "$TUNNEL_KNOWN_HOSTS"
  forward_bind="$(host_for_forward "$LOCAL_BIND")"
  forward_dest="$(host_for_forward "$DEST_HOST")"
  env_tmp="$work_dir/forward.env"
  printf 'SSH_BIN=%s\nSSH_HOST=%s\nSSH_PORT=%s\nSSH_USER=%s\nSSH_KEY=%s\nKNOWN_HOSTS=%s\nLOCAL_BIND=%s\nLOCAL_PORT=%s\nDEST_HOST=%s\nDEST_PORT=%s\n' \
    "$ssh_bin" "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$TUNNEL_KEY" "$TUNNEL_KNOWN_HOSTS" "$LOCAL_BIND" "$LOCAL_PORT" "$DEST_HOST" "$DEST_PORT" > "$env_tmp"
  install -o root -g root -m 0600 "$env_tmp" "$TUNNEL_CONFIG.new"

  wrapper_tmp="$work_dir/anytls-tunnel-start"
  cat > "$wrapper_tmp" <<'WRAPPER'
#!/bin/sh
set -eu
bind_host="$LOCAL_BIND"
destination_host="$DEST_HOST"
case "$bind_host" in *:*) bind_host="[$bind_host]" ;; esac
case "$destination_host" in *:*) destination_host="[$destination_host]" ;; esac
forward="$bind_host:$LOCAL_PORT:$destination_host:$DEST_PORT"
exec "$SSH_BIN" -F /dev/null -N -T \
  -L "$forward" \
  -p "$SSH_PORT" \
  -i "$SSH_KEY" \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS" \
  -o GlobalKnownHostsFile=/dev/null \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ConnectTimeout=15 \
  -o LogLevel=ERROR \
  -l "$SSH_USER" "$SSH_HOST"
WRAPPER
  chmod 0755 "$wrapper_tmp"

  service_tmp="$work_dir/anytls-tunnel.service"
  cat > "$service_tmp" <<'UNIT'
[Unit]
Description=Iran to foreign AnyTLS TCP forwarding tunnel
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
    systemctl stop "$TUNNEL_UNIT"
  fi
  mv -f -- "$TUNNEL_CONFIG.new" "$TUNNEL_CONFIG"
  install -d -o root -g root -m 0755 /usr/local/libexec
  install -o root -g root -m 0755 "$wrapper_tmp" "$TUNNEL_WRAPPER.new"
  mv -f -- "$TUNNEL_WRAPPER.new" "$TUNNEL_WRAPPER"
  install -o root -g root -m 0644 "$service_tmp" "$TUNNEL_SERVICE_FILE.new"
  mv -f -- "$TUNNEL_SERVICE_FILE.new" "$TUNNEL_SERVICE_FILE"

  systemctl daemon-reload
  if ! systemctl enable --now "$TUNNEL_UNIT"; then
    fail 'Tunnel setup was saved, but the service could not start. Review its logs.'
    systemctl status "$TUNNEL_UNIT" --no-pager || true
    journalctl -u "$TUNNEL_UNIT" -n 40 --no-pager || true
    pause
    return 1
  fi

  header
  printf '%sTunnel service is active.%s\n\n' "$GREEN" "$RESET"
  printf 'Clients should connect to the Iran server public IP on TCP port %s.\n' "$LOCAL_PORT"
  printf 'Allow that TCP port in the Iran server firewall and hosting provider firewall.\n'
  printf 'Service commands are available in this panel under SSH tunnel management.\n'
  printf 'The remote AnyTLS server must be running and its SSH account must permit this forwarding.\n'
  pause
}

tunnel_menu() {
  local choice
  while true; do
    header
    printf 'Iran to foreign SSH tunnel\n\n'
    printf 'Service status: %s\n' "$(unit_state "$TUNNEL_UNIT")"
    printf '\n1) Set up or update the tunnel\n2) Manage tunnel service\n3) Show tunnel configuration\n0) Back\n'
    read -r -p 'Select an option: ' choice
    case "$choice" in
      1) setup_tunnel || true ;;
      2)
        if unit_installed "$TUNNEL_UNIT"; then
          unit_menu "$TUNNEL_UNIT" 'Iran to foreign SSH tunnel'
        else
          printf '%sTunnel is not configured yet.%s\n' "$YELLOW" "$RESET"
          pause
        fi
        ;;
      3)
        if [[ -r "$TUNNEL_CONFIG" ]]; then
          printf '\n'
          sed -E 's/^(SSH_KEY|KNOWN_HOSTS)=.*/\1=[protected]/' "$TUNNEL_CONFIG"
        else
          printf '%sNo tunnel configuration found.%s\n' "$YELLOW" "$RESET"
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
  printf 'Iran-to-abroad tunnel commands:\n'
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
    printf 'SSH tunnel:    %s\n\n' "$(unit_state "$TUNNEL_UNIT")"
    printf '1) AnyTLS server management\n2) Iran-to-abroad SSH tunnel management\n3) Show command reference\n0) Exit\n'
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

if [[ "$#" -gt 0 && "$1" == '--setup-tunnel' ]]; then
  shift
  setup_tunnel || true
fi
main_menu
