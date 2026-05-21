#!/usr/bin/env bash
set -uo pipefail

WLAN="${WLAN:-wlan0}"

# Ensure /share output dir exists for cloudcutter's symlinked configured-devices.
mkdir -p /share/cloudcutter-configured-devices

cleanup() {
  echo "[cloudcutter-addon] === cleanup ==="
  # setup_apmode.sh writes its pidfiles to $(pwd) when launched from /opt/cloudcutter/src.
  for pidfile in /opt/cloudcutter/src/hostapd.pid /opt/cloudcutter/src/dnsmasq.pid /tmp/cc-ttyd.pid; do
    if [[ -f "$pidfile" ]]; then
      kill -TERM "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
    fi
  done
  # mosquitto is launched by setup_apmode.sh without a pidfile.
  MOSQ_PID=$(pgrep -x mosquitto 2>/dev/null | head -n1 || true)
  [[ -n "${MOSQ_PID:-}" ]] && kill -TERM "$MOSQ_PID" 2>/dev/null || true
  nmcli device set "$WLAN" managed yes 2>/dev/null || true
  echo "[cloudcutter-addon] cleanup done"
}
trap cleanup EXIT

# Release wlan0 from NetworkManager so hostapd / setup_apmode.sh can claim it later.
nmcli device set "$WLAN" managed no 2>/dev/null || echo "warn: could not set $WLAN unmanaged"

# ttyd as child (NOT exec) so the trap fires on shutdown.
ttyd -W -p 7681 -t titleFixed=Cloudcutter -t fontSize=14 \
  bash -lc 'cd /opt/cloudcutter && exec bash' &
TTYD_PID=$!
echo "$TTYD_PID" > /tmp/cc-ttyd.pid
echo "[cloudcutter-addon] ttyd up on :7681 (ingress, pid=$TTYD_PID)"
wait "$TTYD_PID"
