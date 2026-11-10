# AnyTLS-Go Server Installer

An interactive installer for the [AnyTLS-Go](https://github.com/anytls/anytls-go) server on Linux systems using systemd.

## Quick install

Run this in an interactive SSH session. It downloads the installer from this repository to a temporary file, runs it, and removes the temporary file when it exits:

```bash
tmp_script="$(mktemp)" || exit 1
trap 'rm -f "$tmp_script"' EXIT
curl -fsSL "https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh" -o "$tmp_script" && sudo bash "$tmp_script"
```

The installer downloads the latest stable official AnyTLS-Go release from GitHub, prompts for the server listen IP and port, asks for a password of at least 16 characters without echoing it to the terminal, then installs and enables the `anytls` systemd service. Keep the default IP `0.0.0.0` to listen on all IPv4 interfaces. Allow the selected TCP port in both the server firewall and your hosting provider's firewall.

## Manage the service

```bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f
```

The service is enabled to start automatically at boot. Its password configuration is stored in `/etc/anytls/anytls.env`, readable only by root.

## Requirements and limitations

- Linux with systemd and root access
- `curl` and `python3`
- `amd64` or `arm64` architecture

This installer installs the AnyTLS-Go reference server. The upstream project warns that its sample configuration assumes there is no man-in-the-middle attack. Review the project's security notes before using it for sensitive traffic.
