#!/usr/bin/env python3
"""Export single-password AnyTLS-Go sing-box client profiles."""

import argparse
import base64
import ipaddress
import json
import os
import re
import urllib.parse
from pathlib import Path


ENV = Path("/etc/anytls/anytls.env")
CLIENT_DIR = Path("/root/anytls-clients")
DEFAULT_SNI = "www.cloudflare.com"
FINGERPRINTS = {"android": "android", "ios": "ios", "windows": "chrome"}


def read_env():
    values = {}
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    if values.get("ANYTLS_BACKEND", "anytls-go") == "sing-box":
        raise ValueError("Switch the server back to AnyTLS-Go before exporting profiles.")
    return values


def validate_host(value):
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        label = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
        if len(value) > 253 or not re.fullmatch(label + r"(?:\." + label + r")*\.?", value):
            raise ValueError("The server address or SNI is invalid.")
        return value


def export(server, port, sni, variant):
    values = read_env()
    try:
        password = base64.b64decode(values["ANYTLS_PASSWORD_B64"], validate=True).decode("utf-8")
    except Exception as error:
        raise ValueError("The AnyTLS-Go password could not be read from the server settings.") from error
    if len(password) < 16:
        raise ValueError("The saved AnyTLS-Go password is invalid.")
    server = validate_host(server)
    sni = validate_host(sni or DEFAULT_SNI)
    if not 1 <= port <= 65535:
        raise ValueError("The AnyTLS port must be between 1 and 65535.")

    CLIENT_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CLIENT_DIR, 0o700)
    variant_dir = CLIENT_DIR / variant
    variant_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(variant_dir, 0o700)
    profile_name = "AnyTLS-Go"
    tls = {
        "enabled": True,
        "server_name": sni,
        "insecure": True,
        "alpn": ["h2", "http/1.1"],
    }
    paths = []
    for platform, fingerprint in FINGERPRINTS.items():
        config = {
            "log": {"level": "info", "timestamp": True},
            "dns": {
                "servers": [{"type": "udp", "tag": "remote-dns", "server": "1.1.1.1", "detour": profile_name}],
                "final": "remote-dns",
            },
            "inbounds": [
                {
                    "type": "tun",
                    "tag": "tun-in",
                    "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                    "auto_route": True,
                    "strict_route": True,
                },
                {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080},
            ],
            "outbounds": [
                {
                    "type": "anytls",
                    "tag": profile_name,
                    "server": server,
                    "server_port": port,
                    "password": password,
                    "tls": {**tls, "utls": {"enabled": True, "fingerprint": fingerprint}},
                },
                {"type": "direct", "tag": "direct"},
            ],
            "route": {"auto_detect_interface": True, "final": profile_name},
        }
        platform_dir = variant_dir / platform
        platform_dir.mkdir(mode=0o700, exist_ok=True)
        os.chmod(platform_dir, 0o700)
        path = platform_dir / f"{profile_name}.json"
        path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.chmod(path, 0o600)
        paths.append(str(path))

    host = f"[{server}]" if ":" in server else server
    query = urllib.parse.urlencode({"sni": sni, "insecure": "1"})
    uri = (f"anytls://{urllib.parse.quote(password, safe='')}@{host}:{port}/?{query}"
           f"#{urllib.parse.quote(profile_name, safe='')}")
    qr_path = variant_dir / f"{profile_name}.png"
    print(uri)
    print("\n".join(paths))
    print(qr_path)


def main():
    parser = argparse.ArgumentParser(description="Export AnyTLS-Go client profiles")
    subparsers = parser.add_subparsers(dest="action", required=True)
    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("--server", required=True)
    export_parser.add_argument("--port", required=True, type=int)
    export_parser.add_argument("--sni", default=DEFAULT_SNI)
    export_parser.add_argument("--variant", required=True, choices=("iran-gost-tunnel", "germany-direct"))
    args = parser.parse_args()
    try:
        export(args.server, args.port, args.sni, args.variant)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
