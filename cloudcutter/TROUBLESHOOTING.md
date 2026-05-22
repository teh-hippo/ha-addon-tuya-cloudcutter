# Troubleshooting

Detailed gotchas + workarounds for issues that come up during cloudcutter
flashes on HAOS. The main `README.md` lists these at a one-line summary
level; this file has the actual commands and context.

## Port 80 / 443 / 4433 collisions

cloudcutter's `update_firmware` and `configure_local_device` commands
start a tornado HTTPS server on `0.0.0.0:80`, `:443`, and `:4433`. The
add-on runs in host network mode (`host_network: true`), so wildcard
binds collide with any other host-network service holding those ports.

**The big one: NGINX SSL proxy add-on (`core_nginx_proxy`)** holds
`0.0.0.0:443` for HA UI SSL termination. cloudcutter fails to start with
`OSError: [Errno 98] Address already in use`.

**Fix:**

```bash
ssh -p 2222 root@<HAOS_IP> 'ha apps stop core_nginx_proxy'
```

⚠ **This severs remote HTTPS access** (e.g.
`https://ha.your-domain.example`) for the duration. You'll still be able
to reach HA via port 8123 directly on the LAN, and via the cloudcutter
add-on's own ingress UI / SSH. Restart NGINX after `update_firmware` /
`configure_local_device` finishes:

```bash
ssh -p 2222 root@<HAOS_IP> 'ha apps start core_nginx_proxy'
```

Other commonly-bound add-ons to check:

```bash
# From the cloudcutter add-on shell:
ss -tln | grep -E ':(80|443|4433)\b'
```

If anything shows up before you start a flash, identify and stop it.

There is an upstream cloudcutter patch in flight (and shipped as a
`patches/` overlay in this add-on) that binds to `args.ip` instead of
`0.0.0.0`, which mostly fixes this — but the wildcard listener still
covers the specific IP, so stopping the conflicting service is still
required.

## `exploit_device` fails with `KeyError: 'profile'`

cloudcutter expects a **combined** profile JSON
`{slug, device, profile}`, not the bare profile file from
`device-profiles/profiles/`. The upstream `tuya-cloudcutter.sh` wrapper
builds this for you. If you're invoking the Python module directly
(which the add-on README recommends), build the combined file via the
same upstream tooling:

```bash
cd /opt/cloudcutter/src
pipenv run python -m get_input \
  --workdir /opt/cloudcutter \
  --output /tmp/combined.json \
  write-profile <device-slug>
export PROFILE=/tmp/combined.json
```

`<device-slug>` is the filename (without `.json`) from
`/opt/cloudcutter/device-profiles/devices/`, e.g.
`tuya-generic-sk20-star-projector-v1.1.2`.

If you have multiple linked profile variants in the device JSON, the
upstream `write-profile` picks the first; for the others use `pipenv run
python -m get_input ... choose-profile` interactively.

## `configure_wifi` doesn't persist on the device

`configure_wifi` is a one-shot UDP payload. The device tries the
specified SSID for a short window (often ~60s of retries), then reverts
to its previous Wi-Fi configuration on the next boot. **If your
cloudcutter AP isn't already up and stable when the device tries to
join, the device gives up and you have to start over from the AP-mode
dance.**

Treat `configure_wifi → setup_apmode → update_firmware` as a single
atomic sequence. The order is:

1. Connect to device's `A-*` AP from `wlan0`.
2. Send `configure_wifi cloudcutterflash abcdabcd`.
3. Disconnect, release `wlan0` from NetworkManager, run
   `setup_apmode.sh`.
4. Start `update_firmware`.

No long pauses between steps. If `setup_apmode.sh` fails (next section),
the device's retry window may expire before you get the AP up.

## `setup_apmode.sh` fails silently first run

Symptoms in output:

```text
nl80211: kernel reports: Match already configured
...
Could not set channel for kernel driver
Interface initialization failed
wlan0: interface state UNINITIALIZED->DISABLED
```

Cause: leftover wiphy / nl80211 state from NetworkManager. Fix: cycle
the interface before invoking the script:

```bash
nmcli device disconnect wlan0 2>/dev/null
nmcli device set wlan0 managed no
ip addr flush dev wlan0
ip link set wlan0 down
sleep 3
ip link set wlan0 up
bash setup_apmode.sh wlan0 false
```

Verify it actually came up cleanly **before** moving on:

```bash
iw dev wlan0 info | grep -E "type|channel|ssid"
# expect: type AP, channel 6 (2437 MHz), ssid cloudcutterflash
ip -4 addr show wlan0 | grep inet
# expect: 10.204.0.1/24 + 10.204.0.2/32 + 10.204.0.3/32
ps -ef | grep -E "hostapd|dnsmasq|mosquitto" | grep -v grep
# expect: 3 lines
```

If any of these are missing, `update_firmware` will appear to start but
the device won't be able to talk to it.

## Repeated `setup_apmode.sh` invocations break mosquitto

Upstream `setup_apmode.sh` (as of this writing) blindly appends a
`listener 1883 0.0.0.0` line to `/etc/mosquitto/mosquitto.conf` and runs
`mkdir /run/mosquitto` (not `-p`). On the second run within the same
add-on container lifetime, both fail / produce duplicate config.

Workaround: restart the add-on between flashes (the container restart
resets `/etc/mosquitto/mosquitto.conf` to its baseline). Or apply the
overlay patches in `cloudcutter/patches/` (when shipped) which switch
to a dedicated config file under `/etc/mosquitto/conf.d/` and use
`mkdir -p`.

## ESPHome OTA fails after a cloudcutter flash

If your ESPHome YAML has a bare `ota:` block with no platform:

```yaml
ota:
```

…ESPHome 2026.x dashboards / CLI default to the `web_server` OTA
platform, which uploads UF2 firmware via HTTP multipart on port 80.
**This fails on BK7231T LibreTiny devices** — `web_server` OTA can't
process UF2-format firmware on this chip.

Fix: declare the native OTA platform explicitly:

```yaml
ota:
  - platform: esphome
```

This uses the ESPHome native API protocol on port 8892, which speaks the
correct upload format for LibreTiny chips. After redeploying via a
serial flash or another OTA path, subsequent OTAs work normally.

The first post-cloudcutter OTA is also the first chance to fix this if
the staging firmware was compiled without it — re-stage a corrected
staging binary in `/share/cloudcutter-firmware/<device>.ota.ug.bin` and
re-run `update_firmware`.

## OTA fails at 90%+ with chunk-ack timeout

Symptom:

```text
ERROR receiving chunk result response: timed out
WARNING Failed to upload to ['<device-ip>']
```

…after the progress bar reaches 90% or higher. This is usually a
**transient 2.4 GHz packet loss** issue, not a fundamental upload
problem. If the device is still reachable (`ping`, port 6053 open) and
still on the previous firmware, just retry the install.

ESPHome's chunk-ack timeout is already 90s and isn't the bottleneck;
the issue is bursty packet loss on the wireless link. Moving HA / the
client to 5 GHz or wired won't help (the **device** is the constrained
endpoint). Patience + retries is the working strategy.

## HA doesn't auto-discover the post-flash ESPHome device

Symptoms: the device boots ESPHome, the dashboard shows it Online,
`galaxy.local` resolves, port 6053 is open — but HA's
Settings → Devices & Services has no new "Discovered" card for it.

Manual flow:

1. HA → Settings → Devices & Services → **Add Integration**.
2. Search for **ESPHome**.
3. Enter the device IP (or mDNS name) and port `6053`.
4. Confirm — HA picks up the device's API encryption key from the
   matching `api_encryption_key` secret if it's identical.

If you prefer scripting it via the REST API:

```bash
HA_URL=https://homeassistant.local:8123    # or your HA URL
HA_TOKEN=<your HA long-lived access token>

FLOW=$(curl -sk -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "$HA_URL/api/config/config_entries/flow" \
  -d '{"handler":"esphome"}' | jq -r .flow_id)

curl -sk -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "$HA_URL/api/config/config_entries/flow/$FLOW" \
  -d '{"host":"<device-ip>","port":6053}'
```

## Lost the `.deviceconfig` file

After `exploit_device`, the per-device keys live in
`/share/cloudcutter-configured-devices/<uuid>.deviceconfig`. If you lose
this file and the device is still on cloudcutter staging firmware (i.e.
you haven't run `update_firmware` yet), you can no longer talk to it
locally with the new keys.

Workarounds: re-run the AP-mode dance + `exploit_device` to mint new
keys (the device accepts this), or proceed with `update_firmware` using
a freshly-extracted profile.

`/share/cloudcutter-configured-devices/` is in HA's `/share/` mount,
so it's covered by HA backups by default. Worth confirming your backup
strategy includes it.

## Wlan0 stuck in unmanaged / AP mode after add-on crash

If the add-on crashes mid-flash and `wlan0` is left in unmanaged or AP
state, from the HAOS host shell:

```bash
ssh -p 2222 root@<HAOS_IP>
nmcli device set wlan0 managed yes
```

No reboot required. If the addon container itself won't stop cleanly:

```bash
ha apps stop d52dc666_tuya_cloudcutter
nmcli device set wlan0 managed yes
```

## Device firmware family mismatch

Today's cloudcutter ships exploits for BK7231T (Beken), BK7231N, and
RTL8720CF (Realtek, ported November 2025). The OTA binary format
**differs** between families:

| Chip family | Expected OTA filename / format |
|---|---|
| BK7231T / BK7231N | `image_bk7231t_app.ota.ug.bin` (BK "UG" wrapper) |
| RTL8720CF | `image.ota.bin` (Realtek native OTA) |

Don't stage a BK `.ug.bin` for an RTL device or vice versa — cloudcutter
won't validate the magic bytes before serving (yet); the device will
reject mid-flash and may end up in a stuck state. Compile the correct
artefact for your chip family and double-check before staging.
