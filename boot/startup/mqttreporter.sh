#!/bin/sh
# shellcheck shell=sh
# OnionOS startup hook for MQTTReporter.
# Deployed to /mnt/SDCARD/.tmp_update/startup/mqttreporter.sh by install.sh.
# OnionOS's runtime.sh iterates every *.sh under .tmp_update/startup/ on boot.

APP_DIR="/mnt/SDCARD/App/MQTTReporter"
STATE_DIR="$APP_DIR/state"
ENABLED_FLAG="$STATE_DIR/enabled"

[ -e "$ENABLED_FLAG" ] || exit 0

# Prepend Onion's parasyte (glibc 2.28) so Debian armhf binaries find symbols.
PARASYTE="/mnt/SDCARD/.tmp_update/lib/parasyte"
PATH="$APP_DIR/bin:$PATH"
LD_LIBRARY_PATH="$PARASYTE:$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
export PATH LD_LIBRARY_PATH

mkdir -p "$STATE_DIR"

# Volume watcher — parallel reader of /dev/input/event0 to track key presses
# (system.json only persists vol on power-off / menu nav).
nohup setsid sh "$APP_DIR/scripts/vol-watcher.sh" \
    >> "$STATE_DIR/vol-watcher.log" 2>&1 < /dev/null &

# MQTT publish daemon
nohup setsid sh "$APP_DIR/scripts/daemon.sh" \
    >> "$STATE_DIR/daemon.log" 2>&1 < /dev/null &

# Web config UI (busybox httpd on :8088 — configurable via $HTTPD_PORT)
APP_DIR_EXPORT="$APP_DIR" \
nohup setsid sh "$APP_DIR/scripts/httpd.sh" \
    >> "$STATE_DIR/httpd.log" 2>&1 < /dev/null &
