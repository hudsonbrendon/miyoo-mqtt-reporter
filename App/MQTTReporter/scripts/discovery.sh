#!/bin/sh
# shellcheck shell=sh

# device_id
# Echoes a stable identifier for this device.
# Order: $DEVICE_ID > sanitized wlan0 MAC > "miyoominiplus".
# Uses $NET_ADDR_READER (shell snippet) for testability; defaults to reading
# /sys/class/net/wlan0/address.
device_id() {
    if [ -n "${DEVICE_ID:-}" ]; then
        printf '%s' "$DEVICE_ID"
        return 0
    fi
    local reader mac clean
    reader="${NET_ADDR_READER:-cat /sys/class/net/wlan0/address}"
    mac="$(eval "$reader" 2>/dev/null || true)"
    if [ -n "$mac" ]; then
        clean="$(printf '%s' "$mac" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
        printf 'miyoo-%s' "$clean"
        return 0
    fi
    printf 'miyoominiplus'
}
