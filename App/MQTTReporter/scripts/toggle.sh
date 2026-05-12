#!/bin/sh
# shellcheck shell=sh disable=SC1091

APP_DIR="${APP_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_DIR="${STATE_DIR:-$APP_DIR/state}"
ENABLED_FLAG="$STATE_DIR/enabled"
PID_FILE="${PID_FILE:-/tmp/mqttreporter.pid}"

mkdir -p "$STATE_DIR"

do_status() {
    local enabled=0
    local running=0
    [ -e "$ENABLED_FLAG" ] && enabled=1
    if [ -r "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE")"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            running=1
        fi
    fi
    printf 'enabled=%s running=%s\n' "$enabled" "$running"
}

do_start() {
    if [ -r "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE")"
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    touch "$ENABLED_FLAG"
    # Detach so closing the launcher does not kill the daemon.
    nohup setsid sh "$APP_DIR/scripts/daemon.sh" \
        >> "$STATE_DIR/daemon.log" 2>&1 < /dev/null &
}

do_stop() {
    rm -f "$ENABLED_FLAG"
    if [ -r "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE")"
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            # Give it 3s to publish offline + exit.
            for _ in 1 2 3; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 1
            done
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    fi
    rm -f "$PID_FILE"
}

do_toggle() {
    if [ -e "$ENABLED_FLAG" ]; then
        do_stop
    else
        do_start
    fi
}
