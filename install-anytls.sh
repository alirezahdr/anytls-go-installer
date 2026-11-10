#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export LC_ALL=C

readonly REPO_API='https://api.github.com/repos/anytls/anytls-go/releases/latest'
readonly SERVICE_NAME='anytls'
readonly SERVICE_FILE='/etc/systemd/system/anytls.service'
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
  printf 'خطا: %s\n' "$*" >&2
  exit 1
}

for command_name in curl python3 base64 systemctl useradd getent install id; do
  command -v "$command_name" >/dev/null 2>&1 || die "دستور لازم پیدا نشد: $command_name"
done

[[ "$(uname -s)" == 'Linux' ]] || die 'این نصب‌کننده فقط برای Linux است.'
[[ "$EUID" -eq 0 ]] || die 'اسکریپت را با دسترسی root اجرا کنید: sudo bash install-anytls.sh'
[[ -d /run/systemd/system ]] || die 'systemd فعال نیست؛ این نصب‌کننده برای سرویس systemd ساخته شده است.'

if [[ -e "$SERVICE_FILE" || -e "$CONFIG_FILE" || -e "$BIN_FILE" ]]; then
  printf 'یک نصب قبلی AnyTLS پیدا شد. ادامه، تنظیمات IP/پورت/رمز را جایگزین می‌کند.\n'
  read -r -p 'برای ادامه و بازپیکربندی تایپ کنید yes: ' replace_existing
  [[ "$replace_existing" == 'yes' ]] || die 'عملیات لغو شد.'
fi

if [[ -t 0 ]]; then
  read -r -p 'IP شنود سرور [0.0.0.0 برای همه رابط‌های IPv4]: ' SERVER_IP
else
  die 'برای دریافت IP، پورت و رمز، اسکریپت را در ترمینال اجرا کنید.'
fi
SERVER_IP="${SERVER_IP:-0.0.0.0}"

if ! SERVER_IP="$(python3 - "$SERVER_IP" <<'PY'
import ipaddress
import sys

try:
    print(ipaddress.ip_address(sys.argv[1]).compressed)
except ValueError:
    raise SystemExit("IP واردشده معتبر نیست؛ یک IPv4 یا IPv6 وارد کنید.")
PY
)"; then
  die 'IP نامعتبر است.'
fi

while true; do
  read -r -p 'پورت AnyTLS [مثلاً 443 یا 8443]: ' PORT
  if [[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$PORT >= 1 && 10#$PORT <= 65535 )); then
    PORT=$((10#$PORT))
    break
  fi
  printf 'پورت باید عددی بین 1 تا 65535 باشد.\n' >&2
done

while true; do
  read -r -s -p 'رمز AnyTLS (حداقل 16 نویسه): ' PASSWORD
  printf '\n'
  read -r -s -p 'تکرار رمز: ' PASSWORD_CONFIRM
  printf '\n'
  if (( ${#PASSWORD} < 16 )); then
    printf 'رمز باید دست‌کم 16 نویسه داشته باشد.\n' >&2
  elif [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
    printf 'دو رمز یکسان نیستند.\n' >&2
  else
    break
  fi
done
unset PASSWORD_CONFIRM

case "$(uname -m)" in
  x86_64|amd64) ARCH='amd64' ;;
  aarch64|arm64) ARCH='arm64' ;;
  *) die "معماری $(uname -m) در فایل‌های رسمی Release پشتیبانی نمی‌شود؛ amd64 و arm64 پشتیبانی می‌شوند." ;;
esac

TMP_DIR="$(mktemp -d -t anytls-install.XXXXXXXX)"
chmod 0700 "$TMP_DIR"
printf 'در حال دریافت اطلاعات آخرین Release رسمی AnyTLS-Go از GitHub...\n'
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
    raise SystemExit("GitHub پاسخ Release پایدار معتبری برنگرداند.")

version = tag[1:] if tag.startswith("v") else tag
expected_name = f"anytls_{version}_linux_{sys.argv[2]}.zip"
matches = [asset for asset in release.get("assets", []) if asset.get("name") == expected_name]
if len(matches) != 1:
    raise SystemExit(f"فایل رسمی {expected_name} در Release پیدا نشد.")

asset = matches[0]
url = asset.get("browser_download_url", "")
if not url.startswith("https://github.com/anytls/anytls-go/releases/download/"):
    raise SystemExit("نشانی دانلود Release مورد انتظار نیست.")

digest = asset.get("digest", "") or ""
if digest and not digest.startswith("sha256:"):
    raise SystemExit("نوع checksum اعلام‌شده توسط GitHub پشتیبانی نمی‌شود.")

print(tag)
print(url)
print(digest.split(":", 1)[1] if digest else "")
PY
)

(( ${#RELEASE_INFO[@]} == 3 )) || die 'خواندن اطلاعات Release از GitHub ناموفق بود.'
VERSION="${RELEASE_INFO[0]}"
DOWNLOAD_URL="${RELEASE_INFO[1]}"
EXPECTED_SHA256="${RELEASE_INFO[2]}"
[[ "$VERSION" =~ ^v?[0-9A-Za-z._-]+$ ]] || die 'شماره نسخه برگشتی از GitHub نامعتبر است.'
printf 'نسخه %s برای Linux/%s انتخاب شد.\n' "$VERSION" "$ARCH"

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
    raise SystemExit("SHA-256 فایل دانلودشده با checksum اعلام‌شده در GitHub تطبیق ندارد.")

try:
    with zipfile.ZipFile(archive_path) as package:
        candidates = [item for item in package.infolist()
                      if item.filename.rsplit("/", 1)[-1] == "anytls-server" and not item.is_dir()]
        if len(candidates) != 1:
            raise SystemExit("فایل anytls-server به‌طور یکتا در آرشیو پیدا نشد.")
        member = candidates[0]
        mode = member.external_attr >> 16
        if stat.S_ISLNK(mode):
            raise SystemExit("فایل سرور در آرشیو به‌صورت symlink است؛ نصب متوقف شد.")
        with package.open(member) as source, open(output_path, "wb") as target:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                target.write(chunk)
except (OSError, zipfile.BadZipFile) as error:
    raise SystemExit(f"آرشیو دانلودشده معتبر نیست: {error}")

if os.path.getsize(output_path) == 0:
    raise SystemExit("فایل اجرایی دانلودشده خالی است.")
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
[[ "$(id -u anytls)" != '0' ]] || die 'حساب سیستم anytls به‌اشتباه UID صفر دارد؛ نصب متوقف شد.'

if [[ "$SERVER_IP" == *:* ]]; then
  LISTEN="[$SERVER_IP]:$PORT"
else
  LISTEN="$SERVER_IP:$PORT"
fi
PASSWORD_B64="$(printf '%s' "$PASSWORD" | base64 | tr -d '\n')"
unset PASSWORD

printf 'در حال نصب فایل‌ها و ساخت سرویس systemd...\n'
if systemctl is-active --quiet "$SERVICE_NAME"; then
  systemctl stop "$SERVICE_NAME"
fi

install -d -o root -g root -m 0755 /usr/local/bin /usr/local/libexec "$CONFIG_DIR"
install -o root -g root -m 0755 "$SERVER_STAGE" "$BIN_FILE.new"
mv -f -- "$BIN_FILE.new" "$BIN_FILE"

cat > "$TMP_DIR/anytls-server-start" <<'SH'
#!/bin/sh
set -eu
listen="${ANYTLS_LISTEN:?تنظیم ANYTLS_LISTEN موجود نیست}"
encoded_password="${ANYTLS_PASSWORD_B64:?تنظیم رمز موجود نیست}"
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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT
install -o root -g root -m 0644 "$TMP_DIR/anytls.service" "$SERVICE_FILE.new"
mv -f -- "$SERVICE_FILE.new" "$SERVICE_FILE"

systemctl daemon-reload
if ! systemctl enable --now "$SERVICE_NAME"; then
  printf 'راه‌اندازی سرویس ناموفق بود. گزارش اخیر:\n' >&2
  systemctl status "$SERVICE_NAME" --no-pager >&2 || true
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager >&2 || true
  die 'سرویس نصب شد اما فعال نشد؛ گزارش بالا را بررسی کنید.'
fi
systemctl is-active --quiet "$SERVICE_NAME" || die 'سرویس پس از نصب active نشد.'

printf '\nنصب AnyTLS-Go %s کامل شد.\n' "$VERSION"
printf 'آدرس شنود: %s\n' "$LISTEN"
printf 'وضعیت سرویس: '
systemctl is-active "$SERVICE_NAME"
printf '\nفرمان‌های مدیریت سرویس:\n'
printf '  systemctl status anytls\n'
printf '  systemctl start anytls\n'
printf '  systemctl stop anytls\n'
printf '  systemctl restart anytls\n'
printf '  systemctl enable anytls\n'
printf '  systemctl disable anytls\n'
printf '  journalctl -u anytls -f\n'
printf '\nدر فایروال سرور و پنل ارائه‌دهنده، پورت %s را برای TCP مجاز کنید.\n' "$PORT"
