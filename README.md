# VLESS + XHTTP + REALITY Installer

A simple one-click installer for deploying VLESS with XHTTP and REALITY on Ubuntu 22.04 using the latest stable Xray-core release.

## Features

* Installs or updates Xray-core using the official XTLS installer
* Supports VLESS + XHTTP + REALITY
* Automatically generates a UUID, REALITY key pair, and Short ID
* Automatically detects the server's public IPv4 address
* Uses the server IP for both the connection address and XHTTP host
* Supports interactive and fully automatic installation
* Validates the generated Xray configuration before applying it
* Creates a backup of the previous configuration
* Restores the previous configuration if Xray fails to start
* Waits for `apt` and `dpkg` locks instead of removing lock files
* Opens the selected TCP port in UFW when UFW is active
* Prints only the final VLESS configuration link
* Does not generate a QR code
* Does not require an owned domain or CDN

## Requirements

* Ubuntu 22.04
* Root access
* A public IPv4 address
* An Xray-compatible client with XHTTP and REALITY support, such as v2rayNG

## Available Scripts

| File              | Description                                                                     |
| ----------------- | ------------------------------------------------------------------------------- |
| `install.sh`      | Interactive installer that asks for SNI, port, uTLS fingerprint, and XHTTP path |
| `install-auto.sh` | Automatic installer that uses the default values without asking any questions   |

## Interactive Installation

The interactive installer displays the default value inside brackets. Press Enter to use the default value.

```bash
curl -fsSL https://raw.githubusercontent.com/YoungDeveloper2025/vless-xhttp-reality/main/install.sh | sudo bash
```

It asks for:

* SNI
* Port
* uTLS fingerprint
* XHTTP path

## Automatic Installation

The automatic installer uses all default values without asking any questions.

```bash
curl -fsSL https://raw.githubusercontent.com/YoungDeveloper2025/vless-xhttp-reality/main/install-auto.sh | sudo bash
```

## Default Configuration

| Setting          | Default value                 |
| ---------------- | ----------------------------- |
| SNI              | `amp-api-edge.apps.apple.com` |
| Port             | `8443`                        |
| uTLS fingerprint | `edge`                        |
| XHTTP path       | `xk5mv5vF7q?ed=2560`          |
| XHTTP mode       | `auto`                        |
| Xray channel     | `stable`                      |
| Address          | Server public IPv4            |
| XHTTP host       | Server public IPv4            |

## Customizing the Defaults

The default values are defined at the beginning of both scripts:

```bash
DEFAULT_SNI="amp-api-edge.apps.apple.com"
DEFAULT_PORT="8443"
DEFAULT_FINGERPRINT="edge"
DEFAULT_PATH="xk5mv5vF7q?ed=2560"
DEFAULT_MODE="auto"
DEFAULT_REMARK="VLESS-XHTTP-Reality"
XRAY_INSTALL_CHANNEL="stable"
```

Edit these values directly on GitHub whenever you want to change the default configuration.

To install the latest available pre-release version of Xray-core, change:

```bash
XRAY_INSTALL_CHANNEL="stable"
```

to:

```bash
XRAY_INSTALL_CHANNEL="beta"
```

## Output

After a successful installation, the script prints a VLESS link similar to:

```text
vless://UUID@SERVER_IP:8443?encryption=none&security=reality&type=xhttp...
```

The link can be imported directly into supported clients.

## Xray Service Commands

Check service status:

```bash
systemctl status xray
```

Restart Xray:

```bash
systemctl restart xray
```

View recent logs:

```bash
journalctl -u xray -n 50 --no-pager
```

## Important Notes

* Running the installer again generates a new UUID, REALITY key pair, and Short ID.
* Previously generated configuration links will stop working after reinstalling.
* Make sure the selected TCP port is also open in your VPS provider's firewall or security group.
* The installer creates a backup of the existing Xray configuration before replacing it.
* Use this project only on servers and networks you own or are authorized to manage.

## Upstream Projects

* [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
* [XTLS/Xray-install](https://github.com/XTLS/Xray-install)
* [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples)
