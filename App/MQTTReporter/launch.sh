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

# infoPanel does NOT combine --message and --image on the same screen,
# so we show two panels in sequence:
#   1. status + URL + instructions (text)
#   2. QR code (image only)
# Either can be dismissed with B.
text_msg="Status:      $run_label
Broker:      $broker_label
Last publish: $last_label
Device id:    ${device_id:-?}

To configure, open this URL on a phone
or laptop on the same Wi-Fi:

    $URL

Or just press B again to see a QR code
you can scan with your phone camera."

# Generate the QR PNG up-front so panel 2 has it ready.
qr_ready=0
if [ "$ip" != "(no wifi)" ] && [ -x "$QRENCODE" ]; then
    if "$QRENCODE" -o "$QR_PNG" -s 8 -m 3 -l M "$URL" >/dev/null 2>&1; then
        qr_ready=1
    fi
fi

show_text_panel() {
    if [ -x "$INFO_PANEL" ]; then
        "$INFO_PANEL" --title "MQTT Reporter" \
                      --message "$text_msg" \
                      --persistent >/dev/null 2>&1 || true
    else
        printf '%s\n' "$text_msg"
        sleep 6
    fi
}

show_qr_panel() {
    if [ "$qr_ready" != "1" ]; then return; fi
    if [ -x "$INFO_PANEL" ]; then
        "$INFO_PANEL" --title "Scan to configure: $URL" \
                      --image "$QR_PNG" \
                      --persistent >/dev/null 2>&1 || true
    fi
}

show_text_panel
show_qr_panel
