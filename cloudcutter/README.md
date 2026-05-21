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

1. In the **ESPHome Device Builder** add-on, compile the YAML and use the **Install → Manual Download** button to grab `image_<chip>_app.ota.ug.bin`.
2. `scp` it into HA's `/share/cloudcutter-firmware/<device>.ota.ug.bin`.
3. Start (or restart) this add-on. `cc-stage-firmware` symlinks each `/share/cloudcutter-firmware/*` into `/opt/cloudcutter/custom-firmware/` (the path cloudcutter's OTA server hard-codes). Re-run on demand with `bash /usr/local/bin/cc-stage-firmware`.
4. Run the upstream cloudcutter flow (`exploit_device` → `configure_wifi` → `update_firmware`) pointing at your staged filename.

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

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
