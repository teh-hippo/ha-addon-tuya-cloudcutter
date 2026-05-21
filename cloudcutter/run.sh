#!/usr/bin/env bash
set -uo pipefail

WLAN="${WLAN:-wlan0}"

# Ensure /share output dir exists for cloudcutter's symlinked configured-devices.
mkdir -p /share/cloudcutter-configured-devices

# Stage custom firmware into the path cloudcutter hard-codes for OTA serving
# (/work/custom-firmware -> /opt/cloudcutter/custom-firmware). Picks up both
# operator-staged /share/cloudcutter-firmware/ AND auto-discovered ESPHome
# dashboard build artefacts. See script header for precedence + extension
# support details. Re-runnable on demand after compiling in the dashboard.
/usr/local/bin/cc-stage-firmware

cleanup() {
  echo "[cloudcutter-addon] === cleanup ==="
  # setup_apmode.sh writes its pidfiles to $(pwd) when launched from /opt/cloudcutter/src.
  for pidfile in /opt/cloudcutter/src/hostapd.pid /opt/cloudcutter/src/dnsmasq.pid /tmp/cc-sshd.pid /tmp/cc-ttyd.pid; do
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
on_signal() {
  echo "[cloudcutter-addon] received signal; exiting cleanly"
  exit 0
}
trap cleanup EXIT
trap on_signal TERM INT

# Release wlan0 from NetworkManager so hostapd / setup_apmode.sh can claim it later.
nmcli device set "$WLAN" managed no 2>/dev/null || echo "warn: could not set $WLAN unmanaged"

# --- Optional sshd for diagnostics ---------------------------------------
# Off by default. When ssh_authorized_keys is non-empty, start sshd on
# ssh_port (default 22251). Host keys persist in /data/ssh_host_keys/.
SSH_PORT=$(jq -r '.ssh_port // 22251' /data/options.json 2>/dev/null || echo 22251)
mapfile -t SSH_KEYS < <(jq -r '.ssh_authorized_keys[]? // empty' /data/options.json 2>/dev/null || true)
if [[ ${#SSH_KEYS[@]} -gt 0 ]]; then
  mkdir -p /data/ssh_host_keys /root/.ssh /run/sshd
  chmod 700 /root/.ssh
  printf '%s\n' "${SSH_KEYS[@]}" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  for t in rsa ecdsa ed25519; do
    f="/data/ssh_host_keys/ssh_host_${t}_key"
    [[ -f "$f" ]] || ssh-keygen -q -t "$t" -N '' -f "$f"
  done
  cat > /data/sshd_config <<EOF
Port ${SSH_PORT}
ListenAddress 0.0.0.0
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
HostKey /data/ssh_host_keys/ssh_host_rsa_key
HostKey /data/ssh_host_keys/ssh_host_ecdsa_key
HostKey /data/ssh_host_keys/ssh_host_ed25519_key
Subsystem sftp /usr/lib/openssh/sftp-server
LogLevel INFO
EOF
  if /usr/sbin/sshd -t -f /data/sshd_config; then
    /usr/sbin/sshd -D -e -f /data/sshd_config &
    SSHD_PID=$!
    echo "$SSHD_PID" > /tmp/cc-sshd.pid
    echo "[cloudcutter-addon] sshd up on :${SSH_PORT} (pid=$SSHD_PID, ${#SSH_KEYS[@]} key(s))"
  else
    echo "[cloudcutter-addon] sshd config invalid; not starting"
  fi
else
  echo "[cloudcutter-addon] sshd disabled (ssh_authorized_keys is empty)"
fi

# ttyd as child (NOT exec) so the trap fires on shutdown.
ttyd -W -p 7681 -t titleFixed=Cloudcutter -t fontSize=14 \
  bash -lc 'cd /opt/cloudcutter && exec bash' &
TTYD_PID=$!
echo "$TTYD_PID" > /tmp/cc-ttyd.pid
echo "[cloudcutter-addon] ttyd up on :7681 (ingress, pid=$TTYD_PID)"

# Signal-aware exit:
# - supervisor SIGTERM/SIGINT to PID 1 triggers on_signal (exit 0) BEFORE
#   `wait` resumes, so HA UI shows state:stopped not error.
# - if ttyd itself crashes (no signal), `wait` returns ttyd's exit code; we
#   propagate it so the failure surfaces in HA UI as state:error.
wait "$TTYD_PID"
exit $?
