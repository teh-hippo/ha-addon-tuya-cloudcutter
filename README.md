# Tuya Cloudcutter HAOS Add-on Repository

⚠️ **Pioneer status**: first community attempt at wrapping
[`tuya-cloudcutter`](https://github.com/tuya-cloudcutter/tuya-cloudcutter)
as a Home Assistant OS add-on. Use at your own risk.

## Who it's for

Semi-manual: a human operator at the add-on's ingress web terminal, or an
agent driving it via `ssh root@haos 'docker exec addon_<slug> ...'`. The
add-on provides a HAOS-compatible environment for the upstream
`tuya-cloudcutter` Python module, plus minimal `wlan0` lifecycle handling.
**There is no convenience layer** — operators invoke the upstream commands
directly. See the add-on's Documentation tab once installed.

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
| [`cloudcutter`](./cloudcutter/) | HAOS-compatible environment for upstream tuya-cloudcutter |

## Credit

All actual cloudcutter functionality from
[tuya-cloudcutter/tuya-cloudcutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter).
This add-on is glue code only.
