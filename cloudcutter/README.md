# Tuya Cloudcutter HAOS Add-on (pioneer / PoC)

⚠️ **Pioneer status**: first community attempt at wrapping `tuya-cloudcutter` as a HAOS add-on. Use at your own risk.

⚠️ **Highly privileged**: requires `host_network`, `host_dbus`, `apparmor: false`, `/dev/rfkill` device passthrough, and `NET_ADMIN + NET_RAW + SYS_ADMIN`. Effectively root on the host network stack.

⚠️ **Only run manually**, stop when done. Requires HA on **wired Ethernet** — the add-on takes over `wlan0`.

## Changelog

- **v0.3.5**: Reverts the auto-pickup half of v0.3.4. ESPHome HA add-on writes build artefacts to its own private `/data` directory (see `esphome/core/__init__.py` `data_dir()` returning `Path("/data")` when `is_ha_addon()` is True), not to `/config/esphome/.esphome/build/` as v0.3.4 assumed. No cross-add-on mount exposes another addon's `/data`, so the Pass 2 scan never found anything in practice. `cc-stage-firmware` is retained as the operator-facing helper (stale-symlink cleanup + `/share/` staging refresh) and reflects this reality in its header. `config:ro` mount removed from `config.yaml` (it was only there to enable the now-removed Pass 2). For the "compile in dashboard, then flash via cloudcutter" workflow use the dashboard's **Install → Manual Download** button to fetch the binary to your local machine, then `scp` it into `/share/cloudcutter-firmware/<device>.ota.ug.bin`. A future release may implement a proper API approach (call ESPHome dashboard's `/compile` WebSocket + `/download.bin` HTTP via HA ingress).
- **v0.3.4** (deprecated by v0.3.5): Attempted auto-pickup of ESPHome dashboard build artefacts via `config:ro` mount + a Pass 2 in `cc-stage-firmware` that scanned `/config/esphome/.esphome/build/<device>/.pioenvs/<env>/image_*.<ext>`. Architecture turned out to be wrong: in HA add-on mode ESPHome writes to its own private `/data`, which isn't reachable from any other add-on. v0.3.5 keeps the cleaner `cc-stage-firmware` helper but drops the broken Pass 2 and the unneeded `config:ro` mount.
- **v0.3.3**: Auto-symlink firmware staged in `/share/cloudcutter-firmware/*` into `/opt/cloudcutter/custom-firmware/` at startup. Closes a gap where users staging OTA `.bin` files via Home Assistant's `/share/` directory hit a 404 mid-flash because cloudcutter's OTA file handler hard-codes `path="/work/custom-firmware/"` (= `/opt/cloudcutter/custom-firmware/`). Idempotent: `ln -sf` overwrites stale links; upstream-shipped kickstart binaries are only displaced if a user explicitly stages a file with the same basename. Also migrates the README's recovery example from `ha addons stop` to `ha apps stop` (the non-deprecated form).
- **v0.3.2**: Replaced the v0.3.1 partial signal-aware exit (which still produced `state:error` because `wait` returned 143 before the EXIT trap could set the flag) with explicit `TERM`/`INT` traps that exit 0 directly. Clean stop now reliably shows `state:stopped` in Home Assistant; real ttyd crashes still surface as `state:error`.
- **v0.3.1**: Container can now access `/dev/rfkill` for AP-mode bring-up. Patched upstream `setup_apmode.sh` to fix the hostapd channel bug on multi-band radios (e.g. Pi CYW43455) — defaults to 2.4 GHz channel 6 unless `AP_CHANNEL` is pre-exported (e.g. `AP_CHANNEL=1 bash setup_apmode.sh wlan0 true`).
- **v0.3.0**: Optional sshd (off by default; pubkey only) for scripted / agent-driven workflows. See "SSH diagnostics" below.
- **v0.2.0**: Barebones cleanup; trap-based wlan0 / pidfile management. Schema dir + configured-devices symlink stabilised.

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
| `./custom-firmware/` | Stage your `.bin` in HA's `/share/cloudcutter-firmware/`; at addon startup `cc-stage-firmware` symlinks every file there into `/opt/cloudcutter/custom-firmware/` (the path cloudcutter's OTA server hard-codes). Re-run `bash /usr/local/bin/cc-stage-firmware` on demand after changing `/share/`. Upstream-shipped kickstart binaries remain unless your file shares a basename. For "compile in ESPHome dashboard, then flash" workflow: dashboard → device → Install → **Manual Download**, save the `.ota.ug.bin` to your local machine, then `scp` it into `/share/cloudcutter-firmware/`. |
| `./configured-devices/` | `/opt/cloudcutter/configured-devices/` (symlinked to `/share/cloudcutter-configured-devices/` so generated `.deviceconfig` files survive add-on updates) |
| `./` (CWD) | `/opt/cloudcutter/src/` (symlinked as `/work/` for upstream defaults that assume that) |
| `pipenv run python -m cloudcutter …` | same; **must run from `/opt/cloudcutter/src/`** (Pipfile lives there; cd'ing to `/opt/cloudcutter/` causes pipenv to silently create a new empty venv) |

## Entry points

- **Web terminal (ingress)**: HA → Add-ons → Tuya Cloudcutter → "Open Web UI". Drops you in `/opt/cloudcutter/` with a login shell. This is the supported operator surface.
- **Optional sshd** (for scripted / agent-driven workflows): see below.
- **Shell-from-SSH** (only works on hosts with Docker socket exposed to a Terminal add-on, e.g. Advanced SSH & Web Terminal with Protection mode off): `docker exec -it addon_$(docker ps --format '{{.Names}}' | grep tuya_cloudcutter) bash`.

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
docker ps --format '{{.Names}}' | grep tuya_cloudcutter   # confirm gone
nmcli device set wlan0 managed yes
```

## Credit

All actual cloudcutter functionality from [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter). This add-on is glue code only.
