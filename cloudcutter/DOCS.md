# Tuya Cloudcutter add-on — operator guide

> **Source of truth: upstream [INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md).**
> The sequences below are a transcription with HAOS-specific path and
> networking adjustments. **Before each session, open upstream's
> INSTRUCTIONS.md and confirm our steps still match.** If they diverge,
> file an issue against this add-on.
>
> This guide was written against upstream revisions pinned in the
> add-on's Dockerfile (`CLOUDCUTTER_REV` and `DEVICE_PROFILES_REV`).
> See the "Verifying alignment" section at the bottom for the exact SHAs.

## ⚠️ Warnings

- **Pioneer status.** First community HAOS add-on for `tuya-cloudcutter`.
  Things will break.
- **Highly privileged.** `host_network`, `host_dbus`, `apparmor: false`,
  `NET_ADMIN + NET_RAW + SYS_ADMIN`. Effectively root on the host
  network stack.
- **Cuts the cloud forever.** Per upstream: "Using Tuya CloudCutter
  means that you will NO LONGER be able to use Tuya's apps and servers."
- **Run manually, stop when done.** The add-on commandeers `wlan0`.

## Prerequisites

- Home Assistant OS on aarch64 (Raspberry Pi 4 verified).
- HA host on **wired Ethernet** — `wlan0` is taken over.
- WiFi adapter supporting AP mode (Pi 4's CYW43455 works).
- Custom firmware `.bin` (UG or UF2 format) placed in `/share/cloudcutter-firmware/`.
- Device profile slug known (see "Finding your device" below).

## Finding your device

The device profile is the JSON file matching your device's brand/model and
firmware version. Two ways to find it:

1. **By device name** — search the
   [upstream device list](https://github.com/tuya-cloudcutter/tuya-cloudcutter.github.io/tree/master/devices).
2. **By firmware version** — open the Smart Life app, tap the device,
   tap the pencil/⋮ icon, choose "Device Update", note the "Main Module"
   version. See
   [upstream FAQ](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ#how-do-i-find-out-what-firmware-version-my-device-has).

Profile JSONs are mirrored inside the add-on at:

```
/opt/cloudcutter/device-profiles/profiles/
/opt/cloudcutter/device-profiles/devices/
```

List with `ls /opt/cloudcutter/device-profiles/profiles/ | grep <chip>`
(e.g. `bk7231t`, `bk7231n`, `rtl8720cf`).

Before flashing, check the
[Known Patched Firmware list](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/Known-Patched-Firmware) —
if your firmware version is patched, cloudcutter cannot exploit it.

## Putting the device in AP mode

Most devices: toggle power 6× with ~1s between each. A light bulb will
**slow-blink** when it's in AP mode (fast-blink is the wrong mode — keep
power-cycling until it slow-blinks). Details and per-device variants:
[upstream FAQ — slow-blink AP mode](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ#how-do-i-put-my-device-into-slow-blink-ap-mode).

You should see a `SmartLife-XXXX` SSID from the Pi.

## Cut (cloud-detach only — no custom firmware)

> *Cross-check against upstream [INSTRUCTIONS.md § Disabling cloud connection
> & running locally](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md#disabling-cloud-connection--running-locally)
> before running.*

Open the add-on's Web UI (ingress terminal) **or**
`ssh -p 22 root@<haos-ip>` followed by
`docker exec -it addon_<slug> bash`.

```bash
# 1. Claim wlan0
nmcli device set wlan0 managed yes

# 2. Join the device's AP (slow-blinking SmartLife-XXXX)
nmcli device wifi connect SmartLife-XXXX

# 3. Run the exploit (replace <profile>.json with yours)
cd /opt/cloudcutter/src
pipenv run python -m cloudcutter exploit_device \
  /opt/cloudcutter/device-profiles/profiles/<profile>.json

# 4. Bring up the cloudcutterflash AP (NetworkManager hotspot mode)
nmcli device wifi hotspot ifname wlan0 \
  ssid cloudcutterflash password abcdabcd

# 5. Configure local keys + push target SSID
pipenv run python -m cloudcutter configure_local_device \
  --ssid '<your-wifi>' --password '<your-pw>' \
  [--device-id <20-char-tuya-id>] [--local-key <16-char-key>]

# 6. Teardown
nmcli connection down Hotspot
```

Generated keys land at
`/opt/cloudcutter/configured-devices/*.json` →
symlinked to `/share/cloudcutter-configured-devices/` so they survive
add-on updates.

## Flash (custom firmware)

> *Cross-check against upstream [INSTRUCTIONS.md § Flashing custom
> firmware](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md#flashing-custom-firmware)
> before running.*

Same as the cut sequence above, **except step 5 swaps `configure_local_device` for
`update_firmware`**:

```bash
# 5. Flash custom firmware (.bin must be UG or UF2 format)
pipenv run python -m cloudcutter update_firmware \
  /opt/cloudcutter/device-profiles/profiles/<profile>.json \
  /opt/cloudcutter/device-profiles/schemas/<schema>.json \
  /opt/cloudcutter/configured-devices \
  /share/cloudcutter-firmware \
  <firmware-file.bin>
```

Steps 1-4 and 6 are identical to "Cut" above.

## What you'll see during a session

Maps to upstream INSTRUCTIONS.md's numbered narrative (steps 4-12):

1. Device slow-blinks (AP mode); `SmartLife-XXXX` SSID appears.
2. After step 3 (`exploit_device`) the device **freezes** for a moment,
   then reboots back into AP mode. You can speed this up by toggling its
   power once.
3. After step 4 (`hotspot`) the Pi's `wlan0` is broadcasting
   `cloudcutterflash` (password `abcdabcd`).
4. The device joins `cloudcutterflash` on its own (may take ~60 seconds —
   the device retries on a 60-second interval if it misses the first
   window).
5. Step 5 (`configure_local_device` or `update_firmware`) writes the new
   keys / firmware over the local AP connection.
6. The device reboots onto your target SSID. Cloud is severed.

If the device hangs at step 4 for more than 2 minutes: power-cycle it back
into AP mode and use the Smart Life app to push it onto `cloudcutterflash`
manually (see
[upstream FAQ — stuck after DHCP](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ#my-device-gets-stuck-after-dhcp-what-can-i-do)).

## If a step fails

Each step is independently re-runnable. Identify which command failed,
fix the precondition, run it again.

- **`nmcli` won't claim `wlan0`** — `nmcli device set wlan0 managed yes`
  then retry. A reboot of the add-on (not the Pi) clears most stuck states.
- **Device never appears as `SmartLife-XXXX`** — wrong AP mode. Try a
  different power-cycle count, or check the slow-blink FAQ above.
- **`exploit_device` fails / hangs** — check the firmware version against
  [Known Patched Firmware](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/Known-Patched-Firmware).
  See also
  [upstream FAQ index](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ).
- **Device flashed but not responsive** —
  [upstream FAQ entry](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ#i-have-flashed-an-incorrect-firmware-and-my-device-no-longer-responds-what-can-i-do).
- **Want to undo a cut and go back to the cloud?** —
  [upstream FAQ entry](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ#can-i-uncut-a-device-and-connect-it-back-to-tuya)
  (spoiler: no, not easily).

## Where things live (HAOS ↔ upstream)

| HAOS path | Upstream (`tuya-cloudcutter` repo root) |
|---|---|
| `/opt/cloudcutter/src/` | `./src/` |
| `/opt/cloudcutter/device-profiles/profiles/` | `./device-profiles/profiles/` (separate repo) |
| `/opt/cloudcutter/device-profiles/devices/` | `./device-profiles/devices/` (separate repo) |
| `/opt/cloudcutter/configured-devices/` (symlink) | `./configured-devices/` |
| `/share/cloudcutter-firmware/` | `./custom-firmware/` |
| `/share/cloudcutter-configured-devices/` | n/a — HAOS-side persistent store |

## Limits vs upstream

This add-on intentionally does **not** replicate:

- `tuya-cloudcutter.sh` interactive menu (we expose the raw Python module).
- `-r` automatic NetworkManager reset (run `nmcli connection reload` if needed).
- "Find by firmware version" interactive picker (use the upstream device list).
- Multi-arch support — `aarch64` only.

## Verifying alignment with upstream

Run through this before each session, especially after the add-on updates:

1. Open upstream [INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md)
   at the commit pinned in our Dockerfile (`CLOUDCUTTER_REV`, see below).
2. Confirm our **Cut** sequence still maps to upstream §
   *Disabling cloud connection & running locally* (steps 1-13).
3. Confirm our **Flash** sequence still maps to upstream §
   *Flashing custom firmware* (steps 1-5).
4. Confirm the cloudcutter AP is still named `cloudcutterflash` with
   password `abcdabcd`. If renamed, this DOCS.md is wrong — open an issue.
5. Confirm `python -m cloudcutter --help` still lists the subcommands we
   call: `exploit_device`, `configure_local_device`, `update_firmware`.
   If renamed, this DOCS.md is wrong.
6. Confirm generated keys still land in `./configured-devices/`. If the
   path moves upstream, our Dockerfile symlink needs updating too.

## Credits + pinned references

- Upstream repo: [tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter)
- Upstream usage: [INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/INSTRUCTIONS.md)
- Host-specific (Raspberry Pi): [HOST_SPECIFIC_INSTRUCTIONS.md](https://github.com/tuya-cloudcutter/tuya-cloudcutter/blob/main/HOST_SPECIFIC_INSTRUCTIONS.md)
- FAQ: [tuya-cloudcutter wiki FAQ](https://github.com/tuya-cloudcutter/tuya-cloudcutter/wiki/FAQ)
- Device profiles repo: [tuya-cloudcutter/tuya-cloudcutter.github.io](https://github.com/tuya-cloudcutter/tuya-cloudcutter.github.io)

**Pinned upstream revisions** (this DOCS.md was written against these):

- `CLOUDCUTTER_REV` = `7bd6b8b1b0c08d3b7a0929e2bb87dd2a649d7c73`
- `DEVICE_PROFILES_REV` = `7af966ad3fc57b0bcb3318c2cac19d1d746ab454`

Bump those SHAs (and re-validate this doc) when intentionally moving to a
newer upstream.
