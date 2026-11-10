#!/usr/bin/env python3
"""Account manager and sing-box backend migration for anytls-panel."""

import argparse
import base64
import fcntl
import hashlib
import ipaddress
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/etc/anytls")
ENV = ROOT / "anytls.env"
DB = ROOT / "users.json"
CONFIG = ROOT / "config.json"
CERT = ROOT / "server.crt"
KEY = ROOT / "server.key"
WRAPPER = Path("/usr/local/libexec/anytls-server-start")
BIN = Path("/usr/local/bin/anytls-sing-box")
API = "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
SERVICE = "anytls"
CLIENT_DIR = Path("/root/anytls-clients")
TIMER = Path("/etc/systemd/system/anytls-users-expiry.timer")
TIMER_SERVICE = Path("/etc/systemd/system/anytls-users-expiry.service")
DEFAULT_SNI = "www.cloudflare.com"
PLATFORM_FINGERPRINTS = {"android": "android", "ios": "ios", "windows": "chrome"}


def require_root():
    if os.geteuid() != 0:
        raise RuntimeError("Run this command as root or with sudo.")


def acquire_lock():
    fd = os.open("/run/lock/anytls-users.lock", os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def run(command, *, check=True, capture=False):
    result = subprocess.run(command, check=False, text=True, capture_output=capture)
    if check and result.returncode:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(detail or f"Command failed: {' '.join(map(str, command))}")
    return result


def read_env():
    values = {}
    if ENV.exists():
        for line in ENV.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    return values


def read_users(path=DB):
    if not Path(path).exists():
        return []
    users = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(users, list):
        raise ValueError("The account database is invalid.")
    seen = set()
    for user in users:
        if not isinstance(user, dict):
            raise ValueError("An account entry is invalid.")
        name, password = user.get("name"), user.get("password")
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,32}", name):
            raise ValueError("An account name is invalid.")
        if name in seen:
            raise ValueError("Duplicate account names were found.")
        if not isinstance(password, str) or len(password) < 16:
            raise ValueError(f"The password for account {name} is invalid.")
        expiry = user.get("expires_at")
        created = user.get("created_at")
        if expiry is not None and (isinstance(expiry, bool) or not isinstance(expiry, int)):
            raise ValueError(f"The expiration value for account {name} is invalid.")
        if created is not None and (isinstance(created, bool) or not isinstance(created, int)):
            raise ValueError(f"The creation time for account {name} is invalid.")
        seen.add(name)
    return users


def atomic_write(path, content, mode=0o600, group=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content if isinstance(content, bytes) else content.encode("utf-8"))
        os.chmod(temp_name, mode)
        if group is not None:
            import grp

            os.chown(temp_name, 0, grp.getgrnam(group).gr_gid)
        else:
            os.chown(temp_name, 0, 0)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def dump_users(users):
    return json.dumps(users, indent=2, ensure_ascii=False) + "\n"


def active_users(users, now=None):
    now = int(time.time()) if now is None else now
    return [user for user in users if user.get("expires_at") is None or user["expires_at"] > now]


def parse_listen(value):
    if value.startswith("["):
        end = value.find("]")
        if end < 0 or value[end + 1 : end + 2] != ":":
            raise ValueError("The saved IPv6 listen address is invalid.")
        address, port_text = value[1:end], value[end + 2 :]
    else:
        address, separator, port_text = value.rpartition(":")
        if not separator:
            raise ValueError("The saved listen address is invalid.")
    address = str(ipaddress.ip_address(address))
    port = int(port_text)
    if not 1 <= port <= 65535:
        raise ValueError("The saved listen port is invalid.")
    return address, port


def account(name, password, days):
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,32}", name):
        raise ValueError("Use 1-32 letters, numbers, dots, underscores, or hyphens for the account name.")
    if not 0 <= days <= 36500:
        raise ValueError("Validity days must be between 0 and 36500.")
    now = int(time.time())
    return {
        "name": name,
        "password": password,
        "created_at": now,
        "expires_at": now + days * 86400 if days else None,
    }


def build_server_config(users, listen):
    address, port = parse_listen(listen)
    if not users:
        raise ValueError("At least one active account is required.")
    return {
        "log": {"level": "info", "timestamp": True},
        "inbounds": [
            {
                "type": "anytls",
                "tag": "anytls-in",
                "listen": address,
                "listen_port": port,
                "users": [{"name": user["name"], "password": user["password"]} for user in users],
                "tls": {"enabled": True, "certificate_path": str(CERT), "key_path": str(KEY)},
            }
        ],
        "outbounds": [{"type": "direct", "tag": "direct"}],
        "route": {"final": "direct"},
    }


def validate_config(config):
    if not BIN.exists():
        raise RuntimeError("The sing-box server binary is not installed.")
    fd, name = tempfile.mkstemp(prefix="anytls-check-", suffix=".json", dir="/etc/anytls")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(config, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.chmod(name, 0o600)
        run([str(BIN), "check", "-c", name], capture=True)
    finally:
        Path(name).unlink(missing_ok=True)


def install_singbox():
    machine = os.uname().machine
    arch = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(machine)
    if not arch:
        raise RuntimeError(f"Unsupported architecture: {machine}. sing-box supports amd64 and arm64 here.")
    request = urllib.request.Request(API, headers={
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "anytls-go-installer",
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    tag = release.get("tag_name", "")
    if not tag or release.get("draft") or release.get("prerelease"):
        raise RuntimeError("GitHub did not return a stable sing-box release.")
    version = tag.removeprefix("v")
    if not re.fullmatch(r"[0-9A-Za-z._-]+", version):
        raise RuntimeError("The sing-box release version is invalid.")
    asset_name = f"sing-box-{version}-linux-{arch}.tar.gz"
    assets = [asset for asset in release.get("assets", []) if asset.get("name") == asset_name]
    if len(assets) != 1:
        raise RuntimeError(f"Official sing-box archive not found: {asset_name}")
    asset = assets[0]
    url = asset.get("browser_download_url", "")
    digest = asset.get("digest", "")
    if not url.startswith("https://github.com/SagerNet/sing-box/releases/download/"):
        raise RuntimeError("The sing-box download URL is unexpected.")
    if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest or ""):
        raise RuntimeError("GitHub did not provide a valid sing-box SHA-256 digest.")
    print(f"Downloading official sing-box {tag} for Linux/{arch}...")
    request = urllib.request.Request(url, headers={"User-Agent": "anytls-go-installer"})
    with urllib.request.urlopen(request, timeout=300) as response:
        archive = response.read()
    actual = hashlib.sha256(archive).hexdigest()
    if actual.lower() != digest.split(":", 1)[1].lower():
        raise RuntimeError("The sing-box archive SHA-256 does not match GitHub's release digest.")
    with tempfile.TemporaryDirectory(prefix="anytls-sing-box-") as directory:
        archive_path = Path(directory) / "sing-box.tar.gz"
        staged = Path(directory) / "sing-box"
        archive_path.write_bytes(archive)
        with tarfile.open(archive_path, "r:gz") as package:
            candidates = [item for item in package.getmembers()
                          if item.name.rsplit("/", 1)[-1] == "sing-box" and item.isfile()]
            if len(candidates) != 1:
                raise RuntimeError("The release archive did not contain exactly one regular sing-box binary.")
            source = package.extractfile(candidates[0])
            if source is None:
                raise RuntimeError("Could not extract sing-box from the verified archive.")
            staged.write_bytes(source.read())
        if staged.stat().st_size == 0:
            raise RuntimeError("The sing-box binary is empty.")
        staged.chmod(0o755)
        atomic_write(BIN, staged.read_bytes(), 0o755)
    print(f"Installed sing-box {tag}.")


def create_expiry_timer():
    service = """[Unit]
Description=Remove expired AnyTLS accounts

[Service]
Type=oneshot
ExecStart=/usr/local/bin/anytls-users.py expire
"""
    timer = """[Unit]
Description=Check AnyTLS account expiration

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=15s
Unit=anytls-users-expiry.service

[Install]
WantedBy=timers.target
"""
    atomic_write(TIMER_SERVICE, service, 0o644)
    atomic_write(TIMER, timer, 0o644)
    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", "--now", "anytls-users-expiry.timer"])


def deploy_users(users, listen=None, enable_if_inactive=False):
    listen = listen or read_env().get("ANYTLS_LISTEN", "")
    users = active_users(users)
    ROOT.mkdir(parents=True, exist_ok=True)
    if not users:
        atomic_write(DB, dump_users(users), 0o600)
        run(["systemctl", "disable", "--now", SERVICE], check=False)
        CONFIG.unlink(missing_ok=True)
        return
    config = build_server_config(users, listen)
    validate_config(config)
    config_text = json.dumps(config, indent=2, ensure_ascii=False) + "\n"
    old_db = DB.read_bytes() if DB.exists() else None
    old_config = CONFIG.read_bytes() if CONFIG.exists() else None
    was_active = run(["systemctl", "is-active", "--quiet", SERVICE], check=False).returncode == 0
    was_enabled = run(["systemctl", "is-enabled", "--quiet", SERVICE], check=False).returncode == 0
    atomic_write(DB, dump_users(users), 0o600)
    atomic_write(CONFIG, config_text, 0o640, "anytls")
    try:
        if was_active:
            run(["systemctl", "restart", SERVICE], capture=True)
        elif enable_if_inactive:
            run(["systemctl", "enable", "--now", SERVICE], capture=True)
        else:
            run(["systemctl", "start", SERVICE], capture=True)
    except Exception:
        if old_db is None:
            DB.unlink(missing_ok=True)
        else:
            atomic_write(DB, old_db, 0o600)
        if old_config is None:
            CONFIG.unlink(missing_ok=True)
        else:
            atomic_write(CONFIG, old_config, 0o640, "anytls")
        if was_active:
            run(["systemctl", "start", SERVICE], check=False, capture=True)
        else:
            run(["systemctl", "stop", SERVICE], check=False, capture=True)
        run(["systemctl", "enable" if was_enabled else "disable", SERVICE], check=False, capture=True)
        raise


def migrate(name, days):
    require_root()
    if not ENV.exists() or run(["systemctl", "cat", SERVICE], check=False, capture=True).returncode:
        raise RuntimeError("Install the AnyTLS server on this machine before enabling account management.")
    service_was_active = run(["systemctl", "is-active", "--quiet", SERVICE], check=False).returncode == 0
    service_was_enabled = run(["systemctl", "is-enabled", "--quiet", SERVICE], check=False).returncode == 0
    values = read_env()
    if values.get("ANYTLS_BACKEND") == "sing-box" and DB.exists():
        print("The server already uses the sing-box account backend.")
        return
    encoded = values.get("ANYTLS_PASSWORD_B64", "")
    try:
        password = base64.b64decode(encoded, validate=True).decode("utf-8")
    except Exception as error:
        raise RuntimeError("The existing AnyTLS password could not be read; migration stopped.") from error
    users = [account(name, password, days)]
    install_singbox()
    if not shutil.which("openssl"):
        raise RuntimeError("openssl is required to create the sing-box TLS certificate.")
    if not shutil.which("groupadd") or not shutil.which("usermod"):
        raise RuntimeError("groupadd and usermod are required to secure the sing-box files.")
    if run(["getent", "group", "anytls"], check=False, capture=True).returncode:
        run(["groupadd", "--system", "anytls"])
    run(["usermod", "--gid", "anytls", "anytls"])

    listen = values.get("ANYTLS_LISTEN", "")
    config = build_server_config(users, listen)
    ROOT.mkdir(parents=True, exist_ok=True)
    old_files = {}
    for path in (ENV, WRAPPER, CONFIG, DB, CERT, KEY):
        if path.exists():
            old_files[path] = (path.read_bytes(), path.stat().st_mode & 0o777)
    cert_stage = ROOT / ".server.crt.new"
    key_stage = ROOT / ".server.key.new"
    run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
         "-keyout", str(key_stage), "-out", str(cert_stage), "-days", "3650",
         "-subj", "/CN=anytls.local"], capture=True)
    os.chmod(cert_stage, 0o640)
    os.chmod(key_stage, 0o640)
    import grp

    gid = grp.getgrnam("anytls").gr_gid
    os.chown(cert_stage, 0, gid)
    os.chown(key_stage, 0, gid)
    atomic_write(CERT, cert_stage.read_bytes(), 0o640, "anytls")
    atomic_write(KEY, key_stage.read_bytes(), 0o640, "anytls")
    cert_stage.unlink(missing_ok=True)
    key_stage.unlink(missing_ok=True)
    validate_config(config)

    wrapper = "#!/bin/sh\nset -eu\nexec /usr/local/bin/anytls-sing-box run -c /etc/anytls/config.json\n"
    new_env = f"ANYTLS_LISTEN={listen}\nANYTLS_BACKEND=sing-box\n"
    try:
        run(["systemctl", "stop", SERVICE])
        atomic_write(WRAPPER, wrapper, 0o755)
        atomic_write(ENV, new_env, 0o600)
        deploy_users(users, listen)
        create_expiry_timer()
    except Exception:
        run(["systemctl", "stop", SERVICE], check=False)
        for path in (ENV, WRAPPER, CONFIG, DB, CERT, KEY):
            if path in old_files:
                content, mode = old_files[path]
                group = "anytls" if path in (CONFIG, CERT, KEY) else None
                atomic_write(path, content, mode, group)
            else:
                path.unlink(missing_ok=True)
        run(["systemctl", "daemon-reload"], check=False)
        run(["systemctl", "enable" if service_was_enabled else "disable", SERVICE], check=False)
        run(["systemctl", "start" if service_was_active else "stop", SERVICE], check=False)
        raise
    print("Multi-user mode is active. The existing password remains the first account.")


def print_users():
    now = int(time.time())
    for user in read_users():
        expiry = user.get("expires_at")
        state = "no expiry" if expiry is None else (
            "expired" if expiry <= now else
            datetime.fromtimestamp(expiry, timezone.utc).strftime("expires %Y-%m-%d %H:%M UTC")
        )
        print(f"{user['name']}\t{state}")


def add_user(name, days):
    users = active_users(read_users())
    if any(user["name"] == name for user in users):
        raise ValueError("That account name already exists.")
    password = secrets.token_hex(24)
    users.append(account(name, password, days))
    deploy_users(users, enable_if_inactive=len(users) == 1)
    print(password)


def remove_user(name):
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,32}", name):
        raise ValueError("The account name is invalid.")
    users = read_users()
    remaining = [user for user in users if user["name"] != name]
    if len(remaining) == len(users):
        raise ValueError("That account does not exist.")
    deploy_users(remaining)
    for path in CLIENT_DIR.glob(f"{name}-*") if CLIENT_DIR.exists() else ():
        path.unlink(missing_ok=True)
    print(f"Account {name} removed.")


def expire_users():
    require_root()
    if read_env().get("ANYTLS_BACKEND") != "sing-box" or not DB.exists():
        return
    users = read_users()
    remaining = active_users(users)
    if len(remaining) != len(users):
        deploy_users(remaining)
        for user in users:
            if user not in remaining:
                for path in CLIENT_DIR.glob(f"{user['name']}-*") if CLIENT_DIR.exists() else ():
                    path.unlink(missing_ok=True)
        print(f"Expired {len(users) - len(remaining)} AnyTLS account(s).")


def reconfigure(listen):
    require_root()
    if read_env().get("ANYTLS_BACKEND") != "sing-box":
        raise RuntimeError("The multi-user backend is not enabled.")
    parse_listen(listen)
    users = active_users(read_users())
    if not users:
        raise RuntimeError("No active accounts are configured. Add an account before changing the listen address.")
    config = build_server_config(users, listen)
    validate_config(config)
    old_env = ENV.read_bytes()
    atomic_write(ENV, f"ANYTLS_LISTEN={listen}\nANYTLS_BACKEND=sing-box\n", 0o600)
    try:
        deploy_users(users, listen)
    except Exception:
        atomic_write(ENV, old_env, 0o600)
        raise


def validate_host(value):
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        label = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
        if len(value) > 253 or not re.fullmatch(label + r"(?:\." + label + r")*\.?", value):
            raise ValueError("The client server address is invalid.")
        return value


def export_config(name, server, port, sni):
    users = active_users(read_users())
    user = next((entry for entry in users if entry["name"] == name), None)
    if user is None:
        raise ValueError("That account does not exist or has expired.")
    server = validate_host(server)
    port = int(port)
    if not 1 <= port <= 65535:
        raise ValueError("The client port is out of range.")
    sni = validate_host(sni or DEFAULT_SNI)
    tls = {
        "enabled": True,
        "server_name": sni,
        "insecure": True,
        "alpn": ["h2", "http/1.1"],
    }
    CLIENT_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CLIENT_DIR, 0o700)
    paths = []
    for platform, fingerprint in PLATFORM_FINGERPRINTS.items():
        config = {
            "log": {"level": "info", "timestamp": True},
            "dns": {
                "servers": [{"type": "udp", "tag": "remote-dns", "server": "1.1.1.1"}],
                "final": "remote-dns",
            },
            "inbounds": [
                {"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                 "auto_route": True, "strict_route": True},
                {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080},
            ],
            "outbounds": [
                {"type": "anytls", "tag": "anytls-out", "server": server, "server_port": port,
                 "password": user["password"], "tls": {
                     **tls,
                     "utls": {"enabled": True, "fingerprint": fingerprint},
                 }},
                {"type": "direct", "tag": "direct"},
            ],
            "route": {"auto_detect_interface": True, "final": "anytls-out"},
        }
        validate_config(config)
        path = CLIENT_DIR / f"{name}-{platform}.json"
        atomic_write(path, json.dumps(config, indent=2, ensure_ascii=False) + "\n", 0o600)
        paths.append(str(path))
    host = f"[{server}]" if ":" in server else server
    query = urllib.parse.urlencode({"sni": sni, "insecure": "1"})
    uri = (f"anytls://{urllib.parse.quote(user['password'], safe='')}@{host}:{port}/?{query}"
           f"#{urllib.parse.quote(name, safe='')}")
    print(uri)
    print("\n".join(paths))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)
    migrate_parser = sub.add_parser("migrate")
    migrate_parser.add_argument("--name", required=True)
    migrate_parser.add_argument("--days", type=int, required=True)
    add_parser = sub.add_parser("add")
    add_parser.add_argument("--name", required=True)
    add_parser.add_argument("--days", type=int, required=True)
    remove_parser = sub.add_parser("remove")
    remove_parser.add_argument("--name", required=True)
    sub.add_parser("list")
    sub.add_parser("expire")
    config_parser = sub.add_parser("reconfigure")
    config_parser.add_argument("--listen", required=True)
    export_parser = sub.add_parser("export")
    export_parser.add_argument("--name", required=True)
    export_parser.add_argument("--server", required=True)
    export_parser.add_argument("--port", required=True)
    export_parser.add_argument("--sni", default=DEFAULT_SNI)
    args = parser.parse_args()
    try:
        require_root()
        lock_fd = acquire_lock()
        if args.action == "migrate":
            migrate(args.name, args.days)
        elif args.action == "add":
            add_user(args.name, args.days)
        elif args.action == "remove":
            remove_user(args.name)
        elif args.action == "list":
            print_users()
        elif args.action == "expire":
            expire_users()
        elif args.action == "reconfigure":
            reconfigure(args.listen)
        elif args.action == "export":
            export_config(args.name, args.server, args.port, args.sni)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    finally:
        if "lock_fd" in locals():
            os.close(lock_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
