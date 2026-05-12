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
