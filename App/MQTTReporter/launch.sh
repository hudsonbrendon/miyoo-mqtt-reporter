#!/bin/sh
# shellcheck shell=sh disable=SC1091
set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH="$APP_DIR/bin:$PATH"
LD_LIBRARY_PATH="$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH LD_LIBRARY_PATH
. "$APP_DIR/scripts/toggle.sh"

INFO_PANEL="/mnt/SDCARD/.tmp_update/bin/infoPanel"
STATUS_FILE="/tmp/mqttreporter/status.json"
PORT="${HTTPD_PORT:-8088}"

# Read a flat JSON value by key — small enough to do with sed.
_jread() {
    if [ -r "$STATUS_FILE" ]; then
        sed -n 's/.*"'"$1"'":\s*"\?\([^,"}]*\)"\?.*/\1/p' "$STATUS_FILE" | head -n1
    fi
}

_my_ip() {
    ip route get 1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit} }'
}

_age_seconds() {
    [ -n "$1" ] || { printf '?'; return; }
    local now; now=$(date +%s)
    printf '%s' $(( now - $1 ))
}

# Ensure config exists; if not, copy template and inform the user.
if [ ! -r "$APP_DIR/etc/mqtt.conf" ]; then
    cp "$APP_DIR/etc/mqtt.conf.example" "$APP_DIR/etc/mqtt.conf"
    msg="Created etc/mqtt.conf from template. Open http://<device-ip>:$PORT to configure."
    if [ -x "$INFO_PANEL" ]; then
        "$INFO_PANEL" --title "MQTT Reporter" --message "$msg" --auto >/dev/null 2>&1 || true
    else
        printf '%s\n' "$msg"
        sleep 2
    fi
    exit 0
fi

state="$(do_status)"
broker_ok="$(_jread broker_ok)"
last_epoch="$(_jread last_publish_epoch)"
device_id="$(_jread device_id)"
ip="$(_jread ip)"
[ -z "$ip" ] && ip="$(_my_ip)"
[ -z "$ip" ] && ip="(no wifi)"

case "$broker_ok" in
    true)  broker_label="connected" ;;
    false) broker_label="disconnected" ;;
    *)     broker_label="—" ;;
esac

if [ -n "$last_epoch" ] && [ "$last_epoch" != "null" ]; then
    last_label="$(_age_seconds "$last_epoch")s ago"
else
    last_label="never"
fi

if printf '%s' "$state" | grep -q 'running=1'; then
    run_label="ON"
else
    run_label="OFF"
fi

msg="Status: $run_label
Broker: $broker_label   (last $last_label)
Device id: ${device_id:-?}

Open from any phone on the same Wi-Fi:
  http://$ip:$PORT

Configure broker, toggle ON/OFF, and see live status from there."

if [ -x "$INFO_PANEL" ]; then
    "$INFO_PANEL" --title "MQTT Reporter" --message "$msg" --auto >/dev/null 2>&1 || true
else
    printf '%s\n' "$msg"
    sleep 4
fi
