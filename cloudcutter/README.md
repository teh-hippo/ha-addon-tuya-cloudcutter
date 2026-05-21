# Tuya Cloudcutter HAOS Add-on (pioneer / PoC)

⚠️ **Pioneer status**: first community attempt at wrapping `tuya-cloudcutter` as a HAOS add-on. Use at your own risk.

⚠️ **Highly privileged**: requires `host_network`, `host_dbus`, `apparmor: false`, and `NET_ADMIN + NET_RAW + SYS_ADMIN`. Effectively root on the host network stack.

⚠️ **Only run manually**, stop when done. Requires HA on **wired Ethernet** — the add-on takes over `wlan0`.

## What it is

A HAOS-compatible environment for [tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). It ships the upstream Python module plus its system dependencies (`hostapd`, `dnsmasq`, `mosquitto`, NetworkManager) in a single container, exposes a terminal via Home Assistant ingress, and hands `wlan0` back and forth between NetworkManager and `hostapd`. **No convenience layer** — the operator runs the upstream commands directly.

For the actual cut / flash workflow, see upstream:

- [INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md) — canonical command sequence.
- [HOST_SPECIFIC_INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/HOST_SPECIFIC_INSTRUCTIONS.md) — host setup expectations.
- [FAQ wiki](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ) — slow-blink AP mode, stuck-after-DHCP, no-response recovery.
- [Known patched firmware](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/Known-Patched-Firmware) — check before flashing.

## HAOS-specific deltas

The upstream docs assume a Linux host you SSH into; this add-on is the container. Where upstream says *paths and ports*, read these:

| Upstream | This add-on |
|---|---|
| `./profiles/` | `/opt/cloudcutter/device-profiles/profiles/` |
| `./schema/` | `/opt/cloudcutter/device-profiles/schema/` (empty — cloudcutter falls back to defaults) |
| `./custom-firmware/` | `/share/cloudcutter-firmware/` (drop your `.bin` here) |
| `./configured-devices/` | `/opt/cloudcutter/configured-devices/` (symlinked to `/share/cloudcutter-configured-devices/` so generated `.deviceconfig` files survive add-on updates) |
| `./` (CWD) | `/opt/cloudcutter/src/` (symlinked as `/work/` for upstream defaults that assume that) |
| `pipenv run python -m cloudcutter …` | same; run from `/opt/cloudcutter/src/` |

## Entry points

- **Web terminal (ingress)**: HA → Add-ons → Tuya Cloudcutter → "Open Web UI". Drops you in `/opt/cloudcutter/` with a login shell. This is the supported operator surface.
- **Shell-from-SSH** (alternative): from the Terminal & SSH add-on, `docker exec -it addon_$(docker ps --format '{{.Names}}' | grep tuya_cloudcutter) bash`.

## wlan0 lifecycle

The add-on releases `wlan0` from NetworkManager when it starts. **You** put it in AP mode (or back under NM) by running upstream's commands at the right point in the flow — typically:

```bash
nmcli device set wlan0 managed yes        # before joining a SmartLife AP
nmcli device set wlan0 managed no         # before bash setup_apmode.sh wlan0 false
```

On clean addon stop, an EXIT trap kills `hostapd` / `dnsmasq` / `mosquitto` spawned by upstream's `setup_apmode.sh` (pidfiles at `/opt/cloudcutter/src/{hostapd,dnsmasq}.pid`; mosquitto found via `pgrep -x`) and restores `wlan0` to managed.

## HAOS recovery for a stuck wlan0

If the add-on crashes mid-flash and `wlan0` is left under `hostapd` / unmanaged, from the HA host shell (Terminal & SSH add-on):

```bash
ssh -p 2222 root@<HA_IP>
nmcli device set wlan0 managed yes
```

No reboot required. If the addon container itself won't stop cleanly:

```bash
ha addons stop d52dc666_tuya_cloudcutter
docker ps --format '{{.Names}}' | grep tuya_cloudcutter   # confirm gone
nmcli device set wlan0 managed yes
```

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
