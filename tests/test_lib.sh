#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091,SC2154
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../App/MQTTReporter/scripts/lib.sh"

testLogInfoWritesToStderr() {
    . "$LIB"
    out="$(log_info "hello" 2>&1 >/dev/null)"
    assertContains "$out" "hello"
    assertContains "$out" "INFO"
}

testLogErrorWritesToStderr() {
    . "$LIB"
    out="$(log_error "broke" 2>&1 >/dev/null)"
    assertContains "$out" "broke"
    assertContains "$out" "ERROR"
}

testLogInfoIncludesTimestamp() {
    . "$LIB"
    out="$(log_info "x" 2>&1 >/dev/null)"
    # ISO-8601 prefix like 2026-05-12T...
    echo "$out" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
    assertEquals 0 $?
}

testLoadConfigReadsKeyValuePairs() {
    . "$LIB"
    tmp="$(mktemp)"
    cat >"$tmp" <<'EOF'
# comment
MQTT_HOST=broker.lan
MQTT_PORT=1883
MQTT_USER=miyoo
MQTT_PASS=s3cret
INTERVAL=15
EOF
    load_config "$tmp"
    assertEquals "broker.lan" "$MQTT_HOST"
    assertEquals "1883"       "$MQTT_PORT"
    assertEquals "miyoo"      "$MQTT_USER"
    assertEquals "s3cret"     "$MQTT_PASS"
    assertEquals "15"         "$INTERVAL"
    rm -f "$tmp"
}

testLoadConfigIgnoresCommentsAndBlankLines() {
    . "$LIB"
    tmp="$(mktemp)"
    cat >"$tmp" <<'EOF'

# this is a comment
MQTT_HOST=x

  # indented comment
EOF
    load_config "$tmp"
    assertEquals "x" "$MQTT_HOST"
    rm -f "$tmp"
}

testLoadConfigFailsOnMissingFile() {
    . "$LIB"
    rc=0
    load_config /no/such/file 2>/dev/null || rc=$?
    assertNotEquals 0 "$rc"
}

. "$SCRIPT_DIR/shunit2"
