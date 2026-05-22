Patches applied at build time against the cloudcutter source pinned by
`Dockerfile`'s `CLOUDCUTTER_REV`. Applied via `git apply` in the
Dockerfile (the cloudcutter clone is a real git working tree).

The Dockerfile fails the build loudly if any patch fails to apply —
that's the signal that the upstream revision has drifted and the patches
need refreshing (or the upstream fix has landed and the patch can be
dropped).

When upstream merges any of these, delete the corresponding patch file
and bump `CLOUDCUTTER_REV` to a commit that includes the merge.

## Inventory

| File | Issue | Upstream PR status |
|---|---|---|
| `001-bind-args-ip.patch` | `update_firmware` / `configure_local_device` bind tornado HTTP/S servers to wildcard `0.0.0.0`, colliding with anything else holding 80/443/4433 in host-network mode. Bind to `args.ip` (the AP gateway IP) instead. | Not submitted |
| `002-mosquitto-idempotent.patch` | `setup_apmode.sh` uses non-idempotent `mkdir /run/mosquitto` and blindly appends `listener 1883 0.0.0.0` to `/etc/mosquitto/mosquitto.conf` on every invocation. Switch to `mkdir -p` and write to a dedicated `/etc/mosquitto/conf.d/cloudcutter.conf` (picked up via the base config's existing `include_dir` directive). | Not submitted |

## Refreshing patches when upstream drifts

```bash
# 1. Get a current upstream checkout matching the pinned SHA
git clone https://github.com/tuya-cloudcutter/tuya-cloudcutter /tmp/cc
cd /tmp/cc && git checkout <CLOUDCUTTER_REV from Dockerfile>

# 2. Apply the existing patches manually + re-diff
git apply /path/to/cloudcutter/patches/001-bind-args-ip.patch
git diff > /path/to/cloudcutter/patches/001-bind-args-ip.patch
# Repeat for each patch
```

If a patch can't apply, the upstream rev moved the relevant code. Either
hand-merge the change into the new context, or pin `CLOUDCUTTER_REV`
back to a commit that the patches still apply against.
