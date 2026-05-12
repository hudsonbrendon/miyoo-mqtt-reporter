#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC1091
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

. "$SCRIPT_DIR/shunit2"
