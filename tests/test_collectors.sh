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

testReadRamReturnsUsedPercentAndAvailableKb() {
    . "$COL"
    out="$(read_ram "$FIX/proc-meminfo")"
    # format: "<used_percent>|<available_kb>"
    # MemTotal=257784, MemAvailable=124880 -> used%=51 (round)
    assertEquals "51|124880" "$out"
}

testReadRamReturnsEmptyOnMissingFile() {
    . "$COL"
    out="$(read_ram /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testReadCpuReturnsLoad1AndProcsRunning() {
    . "$COL"
    out="$(read_cpu "$FIX/proc-loadavg")"
    # loadavg fixture: "0.42 0.31 0.18 2/95 1234"
    # format: "<load1>|<procs_running>"
    assertEquals "0.42|2" "$out"
}

testReadCpuReturnsEmptyOnMissingFile() {
    . "$COL"
    out="$(read_cpu /no/such/file 2>/dev/null)"
    assertEquals "" "$out"
}

testDetectBatteryPathPicksDirWithTypeBattery() {
    . "$COL"
    out="$(detect_battery_path "$FIX/power-supply-root")"
    assertEquals "$FIX/power-supply-root/axp20x-battery" "$out"
}

testDetectBatteryPathReturnsEmptyOnNoMatch() {
    . "$COL"
    tmp="$(mktemp -d)"
    out="$(detect_battery_path "$tmp" 2>/dev/null)"
    assertEquals "" "$out"
    rmdir "$tmp"
}

. "$SCRIPT_DIR/shunit2"
