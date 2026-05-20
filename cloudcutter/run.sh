#!/usr/bin/env bash
set -uo pipefail

WLAN="${WLAN:-wlan0}"

echo "[cloudcutter-addon] === preflight ==="
for tool in nmcli hostapd dnsmasq iw rfkill ip pipenv ttyd; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ok: $tool"
  else
    echo "  FAIL: $tool not found"
  fi
done
[[ -f /opt/cloudcutter/src/Pipfile.lock ]] && echo "  ok: cloudcutter source" || echo "  FAIL: cloudcutter source missing"

echo
echo "[cloudcutter-addon] === diag: profiles ==="
PROFDIR=/opt/cloudcutter/device-profiles/profiles
DEVDIR=/opt/cloudcutter/device-profiles/devices
PROFCOUNT=$(ls -1 "$PROFDIR" 2>/dev/null | wc -l)
DEVCOUNT=$(ls -1 "$DEVDIR" 2>/dev/null | wc -l)
echo "  profiles dir: $PROFDIR (count=$PROFCOUNT)"
echo "  devices dir:  $DEVDIR (count=$DEVCOUNT)"
GALAXY_PROFILE="oem-bk7231t-light3-laser-nanxin-1.1.2-sdk-1.0.2-40.00.json"
if [[ -f "$PROFDIR/$GALAXY_PROFILE" ]]; then
  echo "  ok: Galaxy profile present ($GALAXY_PROFILE)"
  python3 -c "import json,sys; d=json.load(open('$PROFDIR/$GALAXY_PROFILE')); print('  Galaxy profile fields:', list(d.keys())[:8])"
else
  echo "  FAIL: Galaxy profile missing: $PROFDIR/$GALAXY_PROFILE"
  echo "  bk7231t-light3 candidates present:"
  ls -1 "$PROFDIR" 2>/dev/null | grep -i 'bk7231t-light3' | head -5 | sed 's/^/    /'
fi

echo
echo "[cloudcutter-addon] === diag: cloudcutter python module ==="
cd /opt/cloudcutter/src && pipenv run python3 -m cloudcutter --help 2>&1 | head -25 | sed 's/^/  /' || echo "  (module help failed or no __main__)"
cd /opt/cloudcutter

echo
echo "[cloudcutter-addon] === diag: cc-wrap.py status ==="
python3 /opt/cloudcutter/cc-wrap.py status 2>&1 | sed 's/^/  /'

echo
echo "[cloudcutter-addon] === diag: cc-wrap.py list-profiles --filter bk7231t (head) ==="
python3 /opt/cloudcutter/cc-wrap.py list-profiles --filter bk7231t 2>&1 | head -10 | sed 's/^/  /'

echo
echo "[cloudcutter-addon] === diag end ==="

ORIG_STATE=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$WLAN" '$1==d{print $2}')
echo "[cloudcutter-addon] $WLAN original NM state: ${ORIG_STATE:-unknown}"
echo "$ORIG_STATE" > /tmp/wlan_orig_state

_cleaned=0
cleanup() {
  [[ $_cleaned -eq 1 ]] && return 0
  _cleaned=1
  echo "[cloudcutter-addon] === cleanup ==="
  for pidfile in /tmp/cc-hostapd.pid /tmp/cc-dnsmasq.pid /tmp/cc-ttyd.pid; do
    [[ -f "$pidfile" ]] && kill -TERM "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  done
  case "$(cat /tmp/wlan_orig_state 2>/dev/null)" in
    unmanaged) nmcli device set "$WLAN" managed no 2>/dev/null || true ;;
    *) nmcli device set "$WLAN" managed yes 2>/dev/null || true ;;
  esac
  echo "[cloudcutter-addon] cleanup done"
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

# Set wlan0 unmanaged so we can grab it later
nmcli device set "$WLAN" managed no 2>/dev/null || echo "warn: could not set $WLAN unmanaged"

# ttyd as child (NOT exec) so the trap fires on shutdown
ttyd -W -p 7681 -t titleFixed=Cloudcutter -t fontSize=14 \
  bash -lc 'cd /opt/cloudcutter && exec bash' &
echo $! > /tmp/cc-ttyd.pid
echo "[cloudcutter-addon] ttyd up on :7681 (ingress)"
wait "$(cat /tmp/cc-ttyd.pid)"
