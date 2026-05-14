#!/bin/sh
# shellcheck shell=sh disable=SC1091
set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PARASYTE="/mnt/SDCARD/.tmp_update/lib/parasyte"
PATH="$APP_DIR/bin:$PATH"
LD_LIBRARY_PATH="$PARASYTE:$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH LD_LIBRARY_PATH APP_DIR
. "$APP_DIR/scripts/toggle.sh"

INFO_PANEL="/mnt/SDCARD/.tmp_update/bin/infoPanel"
QRENCODE="$APP_DIR/bin/qrencode"
STATUS_FILE="/tmp/mqttreporter/status.json"
PORT="${HTTPD_PORT:-8088}"
QR_PNG="/tmp/mqttreporter-qr.png"

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

# First-run: bootstrap mqtt.conf from the example.
if [ ! -r "$APP_DIR/etc/mqtt.conf" ]; then
    cp "$APP_DIR/etc/mqtt.conf.example" "$APP_DIR/etc/mqtt.conf"
fi

ip="$(_jread ip)"
[ -z "$ip" ] && ip="$(_my_ip)"
[ -z "$ip" ] && ip="(no wifi)"

state="$(do_status)"
broker_ok="$(_jread broker_ok)"
last_epoch="$(_jread last_publish_epoch)"
device_id="$(_jread device_id)"

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

URL="http://$ip:$PORT"

# Generate a QR code for the config URL. Keep small enough to fit on the
# Mini Plus's 640×480 screen alongside the message text.
qr_arg=""
if [ "$ip" != "(no wifi)" ] && [ -x "$QRENCODE" ]; then
    if "$QRENCODE" -o "$QR_PNG" -s 6 -m 2 -l M "$URL" >/dev/null 2>&1; then
        qr_arg="--image $QR_PNG"
    fi
fi

msg="Daemon: $run_label   Broker: $broker_label
Last publish: $last_label
Device id: ${device_id:-?}

Open on your phone (same Wi-Fi):

   $URL

Scan the QR with your phone camera, or type
the URL above. Press B to close."

if [ -x "$INFO_PANEL" ]; then
    # shellcheck disable=SC2086
    "$INFO_PANEL" --title "MQTT Reporter" --message "$msg" --persistent $qr_arg >/dev/null 2>&1 || true
else
    printf '%s\n' "$msg"
    sleep 6
fi
