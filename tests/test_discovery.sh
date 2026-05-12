#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091,SC2034,SC2154
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISC="$SCRIPT_DIR/../App/MQTTReporter/scripts/discovery.sh"

testDeviceIdRespectsExplicitOverride() {
    . "$DISC"
    DEVICE_ID="manual-id"
    assertEquals "manual-id" "$(device_id)"
    unset DEVICE_ID
}

testDeviceIdSanitizesMac() {
    . "$DISC"
    # Stub `cat` for /sys/class/net/wlan0/address by exporting fake reader.
    NET_ADDR_READER='printf aa:bb:cc:dd:ee:ff' \
        out="$(device_id)"
    assertEquals "miyoo-aabbccddeeff" "$out"
}

testDeviceIdFallsBackWhenNoMac() {
    . "$DISC"
    NET_ADDR_READER='exit 1' out="$(device_id)"
    assertEquals "miyoominiplus" "$out"
}

. "$SCRIPT_DIR/shunit2"
