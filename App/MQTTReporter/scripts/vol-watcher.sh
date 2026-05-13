#!/bin/sh
# shellcheck shell=sh
# vol-watcher.sh — track Miyoo volume key presses, maintain /tmp/live_vol.
#
# Reads /dev/input/event0 in parallel with Onion's keymon (both readers
# get copies of the input stream). Bumps a 0-20 counter on KEY_VOLUMEDOWN
# (114) and KEY_VOLUMEUP (115) press/auto-repeat events. The MQTT daemon
# reads /tmp/live_vol for the up-to-date value.

LIVE_VOL="${LIVE_VOL:-/tmp/live_vol}"
EVDEV="${EVDEV:-/dev/input/event0}"
SYS_JSON_GLOB="/mnt/SDCARD/.tmp_update/config/system/*.json"

init_vol() {
    local cfg v
    for cfg in $SYS_JSON_GLOB; do
        [ -r "$cfg" ] || continue
        v="$(sed -n 's/.*"vol":[[:space:]]*\([0-9]*\).*/\1/p' "$cfg" | head -1)"
        echo "${v:-10}" > "$LIVE_VOL"
        return
    done
    echo "10" > "$LIVE_VOL"
}

bump() {
    local delta cur new
    delta="$1"
    cur="$(cat "$LIVE_VOL" 2>/dev/null)"
    [ -z "$cur" ] && cur=10
    new=$((cur + delta))
    [ "$new" -lt 0 ] && new=0
    [ "$new" -gt 20 ] && new=20
    echo "$new" > "$LIVE_VOL"
}

init_vol

while [ ! -r "$EVDEV" ]; do
    sleep 2
done

while :; do
    raw="$(dd bs=16 count=1 if="$EVDEV" 2>/dev/null | od -An -tu1)"
    if [ -z "$raw" ]; then
        sleep 1
        continue
    fi
    # shellcheck disable=SC2086
    set -- $raw
    [ "$#" -lt 16 ] && continue
    shift 8
    type=$(($2 * 256 + $1))
    code=$(($4 * 256 + $3))
    value=$(($5 + $6 * 256))
    [ "$type" -eq 1 ] || continue
    if [ "$value" -eq 1 ] || [ "$value" -eq 2 ]; then
        case "$code" in
            115) bump 1 ;;
            114) bump -1 ;;
            *) ;;
        esac
    fi
done
