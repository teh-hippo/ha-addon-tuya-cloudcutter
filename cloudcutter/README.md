# Tuya Cloudcutter HAOS Add-on (pioneer / PoC)

⚠️ **Pioneer status**: first community attempt at wrapping `tuya-cloudcutter` as a HAOS add-on. Use at your own risk.

⚠️ **Highly privileged**: requires `host_network`, `host_dbus`, `apparmor: false`, and `NET_ADMIN + NET_RAW + SYS_ADMIN` capabilities. Effectively root on the host network stack.

⚠️ **Only run manually**, stop when done. Requires a HA installation on **wired Ethernet** — the add-on takes over `wlan0`.

## What it does

Wraps [tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter) for HAOS hosts. Lets you exploit Tuya WiFi modules (BK7231T/N, RTL87xx) over-the-air to flash ESPHome / OpenBeken without soldering.

## How to use

1. Install via HA Add-on Store → Repositories → add `https://github.com/teh-hippo/ha-addon-tuya-cloudcutter`
2. Install the "Tuya Cloudcutter" add-on
3. Open the Web UI (ingress)
4. Run `python3 /opt/cloudcutter/cc-wrap.py status` to verify
5. Flash a device: see DOCS.md

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
