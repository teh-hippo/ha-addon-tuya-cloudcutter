#!/usr/bin/env python3
"""Thin wrapper around tuya-cloudcutter's Python module.

Bypasses upstream tuya-cloudcutter.sh / common.sh (which assume docker-in-docker
and systemctl). Calls the cloudcutter Python module directly with explicit args.
Handles hostapd + dnsmasq lifecycle from inside this same container using nmcli
over host D-Bus.

Subcommands (planned):
  status              Print wlan state, cloudcutter source presence, profile count
  list-profiles       List BK7231* / RTL87* profiles
  flash               Run METHOD_FLASH against a connected SmartLife-XXXX AP
                      Args: --profile NAME --firmware /path/to/file.ota.ug.bin

Tonight (Step 0.7): implement `status` and `list-profiles` only. `flash` is
sketched in but not wired to actual hostapd/dnsmasq orchestration until
tomorrow's Phase A actually needs it.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CLOUDCUTTER_ROOT = Path("/opt/cloudcutter")
PROFILES_DIR = CLOUDCUTTER_ROOT / "device-profiles" / "profiles"
DEVICES_DIR = CLOUDCUTTER_ROOT / "device-profiles" / "devices"


def cmd_status(_args):
    print("=== Cloudcutter add-on status ===")
    print(f"  cloudcutter root: {CLOUDCUTTER_ROOT} (exists={CLOUDCUTTER_ROOT.exists()})")
    print(f"  profiles dir:     {PROFILES_DIR} (count={sum(1 for _ in PROFILES_DIR.glob('*.json')) if PROFILES_DIR.exists() else '-'})")
    print(f"  devices dir:      {DEVICES_DIR} (count={sum(1 for _ in DEVICES_DIR.glob('*.json')) if DEVICES_DIR.exists() else '-'})")

    # nmcli wlan state
    try:
        out = subprocess.check_output(["nmcli", "-t", "-f", "DEVICE,STATE", "device"], text=True)
        for line in out.splitlines():
            if line.startswith("wlan"):
                print(f"  wlan: {line}")
    except Exception as exc:
        print(f"  wlan: ERR ({exc})")

    # pidfile presence
    for pf in ["/tmp/cc-hostapd.pid", "/tmp/cc-dnsmasq.pid", "/tmp/cc-ttyd.pid"]:
        print(f"  {pf}: {'present' if os.path.exists(pf) else 'absent'}")


def cmd_list_profiles(args):
    pattern = args.filter or ""
    for f in sorted(PROFILES_DIR.glob("*.json")):
        if pattern and pattern not in f.name:
            continue
        try:
            d = json.loads(f.read_text())
            ver = d.get("firmware", {}).get("version", "?")
            sdk = d.get("firmware", {}).get("sdk", "?")
            print(f"  {f.stem}  ver={ver} sdk={sdk}")
        except Exception:
            print(f"  {f.stem}  (parse error)")


def cmd_flash(args):
    print("flash: not yet wired. Tomorrow's Phase A implements this.")
    print(f"  profile={args.profile}  firmware={args.firmware}")
    sys.exit(2)


def main():
    p = argparse.ArgumentParser(prog="cc-wrap")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(func=cmd_status)
    sp = sub.add_parser("list-profiles")
    sp.add_argument("--filter", help="substring filter on profile filename")
    sp.set_defaults(func=cmd_list_profiles)
    sp = sub.add_parser("flash")
    sp.add_argument("--profile", required=True)
    sp.add_argument("--firmware", required=True)
    sp.set_defaults(func=cmd_flash)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
