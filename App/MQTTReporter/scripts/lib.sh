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
load_config() {
    cfg="$1"
    if [ ! -r "$cfg" ]; then
        log_error "config file not readable: $cfg"
        return 1
    fi
    # Strip comments + blanks, then source.
    tmp="$(mktemp)"
    grep -vE '^[[:space:]]*(#|$)' "$cfg" > "$tmp"
    # shellcheck disable=SC1090
    . "$tmp"
    rm -f "$tmp"
}
