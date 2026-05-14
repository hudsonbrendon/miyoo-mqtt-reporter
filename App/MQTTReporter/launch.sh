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

# Render a single panel that combines the URL (in the title for hand-typing),
# the daemon/broker status (message body), and the QR for phone scanning.
# Earlier two-step approaches showed only the image panel because
# message-only infoPanel screens get dismissed immediately on the Mini Plus.
qr_arg=""
if [ "$ip" != "(no wifi)" ] && [ -x "$QRENCODE" ]; then
    if "$QRENCODE" -o "$QR_PNG" -s 7 -m 4 -l M "$URL" >/dev/null 2>&1; then
        qr_arg="--image $QR_PNG"
    fi
fi

msg="Status: $run_label   Broker: $broker_label
Last publish: $last_label

Open the URL above on a phone or laptop on the same
Wi-Fi network to configure the broker, toggle the
daemon, and choose which entities are published.

Or scan the QR with a phone camera. Press B to close."

if [ -x "$INFO_PANEL" ]; then
    # shellcheck disable=SC2086
    "$INFO_PANEL" \
        --title "MQTT Reporter  ·  $URL" \
        --message "$msg" \
        $qr_arg \
        --persistent \
        >/dev/null 2>&1 || true
else
    printf '%s\n' "$URL"
    printf '%s\n' "$msg"
    sleep 6
fi
