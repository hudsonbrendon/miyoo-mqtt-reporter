#!/bin/sh
# shellcheck shell=sh
# Common helpers for MQTTReporter.
# Sourced by daemon.sh, toggle.sh, launch.sh, tests.

_log() {
    level="$1"; shift
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s [%s] %s\n' "$ts" "$level" "$*" >&2
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

# load_config <path>
# Reads KEY=VALUE lines, ignoring blanks and lines starting with #.
# Exports each KEY into the current shell.
#
# Security: . (source) evaluates shell expressions in values. Caller must
# ensure the config path is trusted (local SD card, owner-controlled).
load_config() {
    local cfg="$1"
    local tmp rc
    if [ ! -r "$cfg" ]; then
        log_error "config file not readable: $cfg"
        return 1
    fi
    tmp="$(mktemp)"
    grep -vE '^[[:space:]]*(#|$)' "$cfg" > "$tmp"
    set -a
    # shellcheck disable=SC1090
    . "$tmp"
    rc=$?
    set +a
    rm -f "$tmp"
    return "$rc"
}

# mqtt_publish <topic> <payload> <qos> <retain:true|false>
# Requires env: MQTT_HOST, MQTT_PORT. Optional: MQTT_USER, MQTT_PASS, KEEPALIVE.
mqtt_publish() {
    local topic="$1"
    local payload="$2"
    local qos="${3:-0}"
    local retain="${4:-false}"

    : "${MQTT_HOST:?MQTT_HOST not set}"
    : "${MQTT_PORT:?MQTT_PORT not set}"

    set -- -h "$MQTT_HOST" -p "$MQTT_PORT" -q "$qos" -t "$topic" -m "$payload"

    if [ -n "${MQTT_USER:-}" ]; then
        set -- "$@" -u "$MQTT_USER" -P "${MQTT_PASS:-}"
    fi

    if [ "$retain" = "true" ]; then
        set -- "$@" -r
    fi

    if [ -n "${KEEPALIVE:-}" ]; then
        set -- "$@" -k "$KEEPALIVE"
    fi

    mosquitto_pub "$@"
}
