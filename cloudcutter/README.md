# Tuya Cloudcutter HAOS Add-on (pioneer / PoC)

⚠️ **Pioneer status**: first community attempt at wrapping `tuya-cloudcutter` as a HAOS add-on. Use at your own risk.

⚠️ **Highly privileged**: requires `host_network`, `host_dbus`, `apparmor: false`, and `NET_ADMIN + NET_RAW + SYS_ADMIN`. Effectively root on the host network stack.

⚠️ **Only run manually**, stop when done. Requires HA on **wired Ethernet** — the add-on takes over `wlan0`.

## What it is

A HAOS-compatible environment for [tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter): same Python module, same flow, **no convenience layer**. You invoke the upstream commands directly from the add-on's web terminal (or via `docker exec`).

## Using it

Open the Documentation tab inside Home Assistant for the cut and flash sequences, or run `cat /opt/cloudcutter/DOCS.md` from the add-on's web terminal. Both transcribe the upstream [INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md) with HAOS-specific path adjustments.

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
