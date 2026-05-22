# Tuya Cloudcutter HAOS Add-on (pioneer / PoC)

⚠️ **Pioneer status**: first community attempt at wrapping `tuya-cloudcutter` as a HAOS add-on. Use at your own risk.

⚠️ **Highly privileged**: requires `host_network`, `host_dbus`, `apparmor: false`, `/dev/rfkill` device passthrough, and `NET_ADMIN + NET_RAW + SYS_ADMIN`. Effectively root on the host network stack.

⚠️ **Only run manually**, stop when done. Requires HA on **wired Ethernet** — the add-on takes over `wlan0`.

## What it is

A HAOS-compatible environment for [tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). The upstream Python module plus its system dependencies (`hostapd`, `dnsmasq`, `mosquitto`, NetworkManager) in a single container, with `wlan0` lifecycle handling. **No convenience layer** — operators run the upstream commands directly.

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
| `./custom-firmware/` | Stage your `.bin` in HA's `/share/cloudcutter-firmware/`. See [ESPHome integration](#esphome-integration). |
| `./configured-devices/` | `/opt/cloudcutter/configured-devices/` (symlinked to `/share/cloudcutter-configured-devices/` so generated `.deviceconfig` files survive add-on updates) |
| `./` (CWD) | `/opt/cloudcutter/src/` (symlinked as `/work/` for upstream defaults that assume that) |
| `pipenv run python -m cloudcutter …` | same; **must run from `/opt/cloudcutter/src/`** (Pipfile lives there) |

## ESPHome integration

For Tuya devices targeted by an existing ESPHome `bk72xx:` / `rtl87xx:` YAML, the flow is:

1. In the **ESPHome Device Builder** add-on, compile the YAML and use the **Install → Manual Download** button to grab the OTA artefact (`image_bk7231t_app.ota.ug.bin` for BK7231 chips, `image.ota.bin` for RTL8720CF). Make sure your YAML's `ota:` block declares `- platform: esphome` — bare `ota:` defaults to web_server, which doesn't handle LibreTiny UF2 OTAs reliably and will block your first post-flash update.
2. `scp` it into HA's `/share/cloudcutter-firmware/<device>.<ext>`.
3. Start (or restart) this add-on. `cc-stage-firmware` symlinks each `/share/cloudcutter-firmware/*` into `/opt/cloudcutter/custom-firmware/` (the path cloudcutter's OTA server hard-codes). Re-run on demand with `bash /usr/local/bin/cc-stage-firmware`.
4. Run the upstream cloudcutter flow (`exploit_device` → `configure_wifi` → `update_firmware`) pointing at your staged filename. Treat steps 2–4 of the upstream flow as one atomic sequence — `configure_wifi` is one-shot and the device has a short retry window.
5. After OTA, HA may not auto-discover the device via zeroconf. Add it manually: Settings → Devices & Services → Add Integration → ESPHome → device IP + port `6053`.

## Known HAOS blockers

These are HAOS-specific and not covered in the upstream docs. See `TROUBLESHOOTING.md` in this directory for commands and context.

- **Stop any add-on binding 80 / 443 / 4433 before `update_firmware`.** Most commonly `core_nginx_proxy` owns `0.0.0.0:443`. Stopping it severs remote HTTPS access until restarted, so use port 8123 directly during the flash.
- **`exploit_device` requires a *combined* `{slug, device, profile}` JSON.** Bare profile files fail with `KeyError: 'profile'`. Use `pipenv run python -m get_input ... write-profile <slug>` to build it.
- **`configure_wifi → setup_apmode → update_firmware` must run as one atomic sequence.** The device only retries the temporary SSID for ~60s before reverting.
- **If `setup_apmode.sh` exits without leaving wlan0 in AP mode, cycle the interface.** `ip link set wlan0 down; sleep 3; ip link set wlan0 up` then retry; verify with `iw dev wlan0 info | grep 'type AP'`.
- **OTA over weak 2.4 GHz can fail at 90%+ with chunk-ack timeouts.** Retry — the device usually stayed on the previous firmware.

## Tested targets

| Chip | Status | Notes |
|---|---|---|
| BK7231T / `bk72xx:` | ✅ Flashed successfully (Galaxy projector, 2026-05-22) | OTA artefact is `.ota.ug.bin`. Use ESPHome native OTA (`ota: - platform: esphome`) for follow-up firmware updates. |
| RTL8720CF / `rtl87xx:` | ❓ Not yet validated with this add-on | Upstream cloudcutter port from Nov 2025. OTA artefact is `.ota.bin` (no `.ug` wrapper). Expect TuyaMCU-class quirks on appliance devices. |

## Entry points

- **Web terminal (ingress)**: HA → Add-ons → Tuya Cloudcutter → "Open Web UI". Drops you in `/opt/cloudcutter/` with a login shell.
- **Optional sshd** (for scripted / agent-driven workflows): see below.

## SSH diagnostics (optional)

The add-on can run its own sshd on the HAOS host network (because of `host_network: true`). This is **off by default** and only starts when you provide at least one authorised public key.

Configure under the add-on's **Configuration** tab:

```yaml
ssh_authorized_keys:
  - ssh-ed25519 AAAA... user@host
ssh_port: 22251
```

Then connect from any LAN host:

```bash
ssh -p 22251 root@<HAOS_IP>
```

You'll land inside the cloudcutter container at `/opt/cloudcutter/` as root.

Notes:

- Pubkey-only auth (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`). Mirrors the official `core_ssh` posture.
- Host keys generated on first start and persisted in `/data/ssh_host_keys/` so they survive add-on upgrades.
- Leave `ssh_authorized_keys: []` to disable sshd entirely (zero attack surface).
- The default port `22251` is arbitrary; change it if it collides with anything else bound on the HAOS host.

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
ha apps stop d52dc666_tuya_cloudcutter
nmcli device set wlan0 managed yes
```

For everything else (port collisions, exploit_device errors, OTA failures,
HA adoption gaps, mosquitto.conf bug), see `TROUBLESHOOTING.md`.

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
