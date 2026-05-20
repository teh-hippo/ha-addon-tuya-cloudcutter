# Tuya Cloudcutter HAOS Add-on Repository

⚠️ **Pioneer status**: first community attempt at wrapping
[`tuya-cloudcutter`](https://github.com/tuya-cloudcutter/tuya-cloudcutter)
as a Home Assistant OS add-on. Use at your own risk.

## Installation

In Home Assistant: Settings → Add-ons → Add-on Store → ⋮ → Repositories,
add:

```
https://github.com/teh-hippo/ha-addon-tuya-cloudcutter
```

Then install the **Tuya Cloudcutter** add-on.

## Add-ons

| Name | Description |
|---|---|
| [`cloudcutter`](./cloudcutter/) | Wraps tuya-cloudcutter for HAOS hosts |

## Requirements

- Home Assistant OS on aarch64 (Raspberry Pi 4 verified)
- Host on wired Ethernet (the add-on takes over `wlan0`)
- WiFi adapter supporting AP mode (CYW43455 verified)

## Credit

All actual cloudcutter functionality from
[tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter).
This add-on is glue code only.
