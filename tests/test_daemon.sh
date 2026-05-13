#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091,SC2154,SC2329
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX="$SCRIPT_DIR/fixtures"
DAEMON="$SCRIPT_DIR/../App/MQTTReporter/scripts/daemon.sh"
COL="$SCRIPT_DIR/../App/MQTTReporter/scripts/collectors.sh"
LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"

testBuildStatePayloadCombinesAllMetrics() {
    . "$LIB"
    . "$COL"
    . "$DAEMON"

    # Stub read_volume since amixer isn't on dev host.
    read_volume() { printf '73'; }

    out="$(build_state_payload \
        "$FIX/power-supply-charging" \
        "$FIX/proc-meminfo" \
        "$FIX/proc-loadavg")"

    # Validate structure with grep — avoids depending on jq.
    echo "$out" | grep -q '"battery":90'   ; assertEquals 0 $?
    echo "$out" | grep -q '"charging":"ON"'; assertEquals 0 $?
    echo "$out" | grep -q '"volume":73'    ; assertEquals 0 $?
    echo "$out" | grep -q '"ram":51'       ; assertEquals 0 $?
    echo "$out" | grep -q '"cpu":0.42'     ; assertEquals 0 $?
}

testBuildStatePayloadEmitsOffWhenDischarging() {
    . "$LIB"
    . "$COL"
    . "$DAEMON"
    read_volume() { printf '20'; }

    out="$(build_state_payload \
        "$FIX/power-supply-ok" \
        "$FIX/proc-meminfo" \
        "$FIX/proc-loadavg")"
    echo "$out" | grep -q '"charging":"OFF"'; assertEquals 0 $?
}

testBuildStatePayloadIncludesTextFieldsAsNullWhenMissing() {
    . "$LIB"
    . "$COL"
    . "$DAEMON"
    read_volume() { printf '50'; }

    out="$(build_state_payload \
        "$FIX/power-supply-charging" \
        "$FIX/proc-meminfo" \
        "$FIX/proc-loadavg")"

    # On the dev host the Miyoo-specific readers don't exist, so brightness/
    # ip/wifi/game must be `null` (or empty string) — the payload must remain
    # valid JSON with all 17 keys.
    echo "$out" | grep -q '"uptime":'       ; assertEquals 0 $?
    echo "$out" | grep -q '"temperature":'  ; assertEquals 0 $?
    echo "$out" | grep -q '"cpu_freq":'     ; assertEquals 0 $?
    echo "$out" | grep -q '"sd_free":'      ; assertEquals 0 $?
    echo "$out" | grep -q '"brightness":'   ; assertEquals 0 $?
    echo "$out" | grep -q '"vbat":'         ; assertEquals 0 $?
    echo "$out" | grep -q '"ibat":'         ; assertEquals 0 $?
    echo "$out" | grep -q '"wifi_rssi":'    ; assertEquals 0 $?
    echo "$out" | grep -q '"wifi_ssid":'    ; assertEquals 0 $?
    echo "$out" | grep -q '"ip":'           ; assertEquals 0 $?
    echo "$out" | grep -q '"core":'         ; assertEquals 0 $?
    echo "$out" | grep -q '"game":'         ; assertEquals 0 $?
}

testJsonStringEscapesQuotes() {
    . "$LIB"
    . "$COL"
    . "$DAEMON"
    out="$(_j_str 'hello "world"')"
    assertEquals '"hello \"world\""' "$out"
}

testJsonStringEmitsNullForEmpty() {
    . "$LIB"
    . "$COL"
    . "$DAEMON"
    out="$(_j_str "")"
    assertEquals 'null' "$out"
}

. "$SCRIPT_DIR/shunit2"
