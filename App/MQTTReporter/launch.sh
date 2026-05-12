#!/bin/sh
# shellcheck shell=sh disable=SC1091
set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$APP_DIR/scripts/toggle.sh"

INFO_PANEL="/mnt/SDCARD/.tmp_update/bin/infoPanel"

_show() {
    if [ -x "$INFO_PANEL" ]; then
        "$INFO_PANEL" --title "MQTT Reporter" --message "$1" --auto >/dev/null 2>&1 || true
    else
        printf '%s\n' "$1"
        sleep 2
    fi
}

# Ensure config exists; if not, copy template and inform the user.
if [ ! -r "$APP_DIR/etc/mqtt.conf" ]; then
    cp "$APP_DIR/etc/mqtt.conf.example" "$APP_DIR/etc/mqtt.conf"
    _show "Created etc/mqtt.conf from template. Edit it via SSH, then re-open this app."
    exit 0
fi

do_toggle
status="$(do_status)"

if printf '%s' "$status" | grep -q 'running=1'; then
    _show "MQTT Reporter: ON ($status)"
else
    _show "MQTT Reporter: OFF ($status)"
fi
