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

# infoPanel renders --image and --message as mutually exclusive modes.
# To show the help text alongside the QR code, ship a pre-rendered help
# PNG plus a dynamic QR PNG and feed both to infoPanel via --images-json.
# infoPanel cycles between the two pages with L/R; A advances; B exits.
# Per-page `title` shows in the header — we put the URL on the QR page.
PAGES_JSON="/tmp/mqttreporter-pages.json"
HELP_PNG_SRC="$APP_DIR/img/help.png"
HELP_PNG_DST="/tmp/mqttreporter-help.png"
QR_PNG_REL_NAME="mqttreporter-qr.png"
QR_PNG_TMP="/tmp/$QR_PNG_REL_NAME"

# images-json resolves each "path" relative to its own dirname, so we
# stage both PNGs in /tmp/ and reference them by basename.
[ -r "$HELP_PNG_SRC" ] && cp "$HELP_PNG_SRC" "$HELP_PNG_DST" 2>/dev/null

qr_ready=0
if [ "$ip" != "(no wifi)" ] && [ -x "$QRENCODE" ]; then
    # -t PNG32 emits 32-bit RGBA PNG; infoPanel's SDL_image can't always
    # render the default 1-bit indexed PNG that qrencode produces.
    if "$QRENCODE" -t PNG32 -o "$QR_PNG_TMP" -s 8 -m 4 -l M "$URL" >/dev/null 2>&1; then
        qr_ready=1
    fi
fi

# Build JSON. If QR generation failed (no IP / qrencode error), only the
# help page is shown.
{
    printf '{"images":['
    sep=""
    if [ -r "$HELP_PNG_DST" ]; then
        printf '%s{"path":"mqttreporter-help.png","title":"MQTT Reporter — Press A for QR"}' "$sep"
        sep=","
    fi
    if [ "$qr_ready" = "1" ]; then
        printf '%s{"path":"%s","title":"%s"}' "$sep" "$QR_PNG_REL_NAME" "$URL"
    fi
    printf ']}'
} > "$PAGES_JSON"

if [ -x "$INFO_PANEL" ] && [ -s "$PAGES_JSON" ]; then
    # NB: do NOT pass --persistent here. In images-json mode it sets
    # wait_confirm=false which makes infoPanel exit after one render
    # (the screen looks stuck because the framebuffer keeps the last
    # frame but no process is alive to read keys). Default behaviour
    # waits for A/B/L/R and exits on B.
    "$INFO_PANEL" \
        --images-json "$PAGES_JSON" \
        --show-theme-controls \
        >/dev/null 2>&1 || true
elif [ -x "$INFO_PANEL" ]; then
    "$INFO_PANEL" \
        --title "MQTT Reporter" \
        --message "Open this URL to configure: $URL

Daemon: $run_label   Broker: $broker_label
Last publish: $last_label" \
        >/dev/null 2>&1 || true
else
    printf 'MQTT Reporter — open %s\n' "$URL"
    sleep 5
fi
