#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX="$SCRIPT_DIR/fixtures"
COL="$SCRIPT_DIR/../App/MQTTReporter/scripts/collectors.sh"

testReadBatteryReturnsCapacityForDischarging() {
    . "$COL"
    out="$(read_battery "$FIX/power-supply-ok")"
    # format: "<capacity>|<charging:true|false>"
    assertEquals "60|false" "$out"
}

testReadBatteryReturnsChargingTrue() {
    . "$COL"
    out="$(read_battery "$FIX/power-supply-charging")"
    assertEquals "90|true" "$out"
}

testReadBatteryReturnsEmptyWhenPathMissing() {
    . "$COL"
    out="$(read_battery /no/such/path 2>/dev/null)"
    assertEquals "" "$out"
}

testParseVolumeExtractsPercent() {
    . "$COL"
    out="$(parse_volume_from < "$FIX/amixer-master.txt")"
    assertEquals "73" "$out"
}

testParseVolumeReturnsEmptyOnGarbage() {
    . "$COL"
    out="$(printf 'no match here\n' | parse_volume_from)"
    assertEquals "" "$out"
}

. "$SCRIPT_DIR/shunit2"
