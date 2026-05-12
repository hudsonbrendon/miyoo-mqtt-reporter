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

setUpMqttStub() {
    STUB_DIR="$(mktemp -d)"
    STUB_LOG="$STUB_DIR/args.log"
    cat > "$STUB_DIR/mosquitto_pub" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$STUB_LOG"
EOF
    chmod +x "$STUB_DIR/mosquitto_pub"
    PATH="$STUB_DIR:$PATH"
    export PATH STUB_DIR STUB_LOG
}

tearDownMqttStub() {
    rm -rf "$STUB_DIR"
}

testMqttPublishCallsMosquittoPubWithBrokerCreds() {
    setUpMqttStub
    . "$LIB"
    MQTT_HOST=test.lan MQTT_PORT=1883 MQTT_USER=u MQTT_PASS=p \
        mqtt_publish "miyoo/x/state" '{"a":1}' 0 false
    args="$(cat "$STUB_LOG")"
    assertContains "$args" "-h test.lan"
    assertContains "$args" "-p 1883"
    assertContains "$args" "-u u"
    assertContains "$args" "-P p"
    assertContains "$args" "-t miyoo/x/state"
    assertContains "$args" '-m {"a":1}'
    tearDownMqttStub
}

testMqttPublishAddsRetainFlagWhenRequested() {
    setUpMqttStub
    . "$LIB"
    MQTT_HOST=h MQTT_PORT=1883 MQTT_USER='' MQTT_PASS='' \
        mqtt_publish "t" "m" 1 true
    args="$(cat "$STUB_LOG")"
    assertContains "$args" "-r"
    assertContains "$args" "-q 1"
    tearDownMqttStub
}

testMqttPublishOmitsAuthWhenUserEmpty() {
    setUpMqttStub
    . "$LIB"
    MQTT_HOST=h MQTT_PORT=1883 MQTT_USER='' MQTT_PASS='' \
        mqtt_publish "t" "m" 0 false
    args="$(cat "$STUB_LOG")"
    assertNotContains "$args" "-u"
    assertNotContains "$args" "-P"
    tearDownMqttStub
}

. "$SCRIPT_DIR/shunit2"
