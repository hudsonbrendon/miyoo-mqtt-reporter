#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091,SC2034,SC2154,SC2329
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

testPublishDiscoveryEmitsFiveRetainedConfigs() {
    LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"
    . "$LIB"
    . "$DISC"

    PUB_LOG="$(mktemp)"
    mqtt_publish() {
        printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$PUB_LOG"
    }

    export DEVICE_ID="miyoo-test"
    publish_discovery
    unset DEVICE_ID

    cnt="$(wc -l < "$PUB_LOG" | tr -d ' ')"
    assertEquals "5" "$cnt"

    # All retained, qos=0
    while IFS='|' read -r topic _payload qos retain; do
        assertEquals "0" "$qos"
        assertEquals "true" "$retain"
        case "$topic" in
            homeassistant/sensor/miyoo-test_battery/config) ;;
            homeassistant/sensor/miyoo-test_volume/config) ;;
            homeassistant/sensor/miyoo-test_ram/config) ;;
            homeassistant/sensor/miyoo-test_cpu/config) ;;
            homeassistant/binary_sensor/miyoo-test_charging/config) ;;
            *) fail "unexpected topic: $topic" ;;
        esac
    done < "$PUB_LOG"
    rm -f "$PUB_LOG"
}

testPublishDiscoveryConfigReferencesStateTopic() {
    LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"
    . "$LIB"
    . "$DISC"

    PUB_LOG="$(mktemp)"
    mqtt_publish() {
        printf '%s\n' "$2" >> "$PUB_LOG"
    }

    export DEVICE_ID="miyoo-test"
    publish_discovery
    unset DEVICE_ID

    grep -q 'miyoo/miyoo-test/state' "$PUB_LOG"
    assertEquals 0 $?
    grep -q '"avty_t":"miyoo/miyoo-test/availability"' "$PUB_LOG"
    assertEquals 0 $?
    rm -f "$PUB_LOG"
}

. "$SCRIPT_DIR/shunit2"
