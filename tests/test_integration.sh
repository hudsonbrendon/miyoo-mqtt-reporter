#!/bin/sh
# shellcheck shell=sh disable=SC1091
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/.."
FIX="$SCRIPT_DIR/fixtures"

if ! command -v mosquitto >/dev/null 2>&1 || ! command -v mosquitto_sub >/dev/null 2>&1; then
    echo "SKIP: mosquitto/mosquitto_sub not installed on dev host."
    exit 0
fi

PORT=11883
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Start broker
cat > "$TMP/mosquitto.conf" <<EOF
listener $PORT
allow_anonymous true
persistence false
log_dest none
EOF
mosquitto -c "$TMP/mosquitto.conf" -d
sleep 1

# 2. Subscribe to everything, log to file
mosquitto_sub -h 127.0.0.1 -p "$PORT" -t '#' -v > "$TMP/received.log" 2>/dev/null &
SUB_PID=$!
sleep 1

# 3. Build a runtime config + override collector paths via env
cat > "$TMP/mqtt.conf" <<EOF
MQTT_HOST=127.0.0.1
MQTT_PORT=$PORT
MQTT_USER=
MQTT_PASS=
INTERVAL=1
DEVICE_ID=miyoo-it
BATTERY_PATH=$FIX/power-supply-charging
EOF

# 4. Run a minimal driver that reuses the daemon helpers but with fixture paths.
#    The host's mosquitto_pub is used (PATH is not overridden with vendored bin).
sh -c "
    set -e
    APP_DIR='$REPO/App/MQTTReporter'
    . \$APP_DIR/scripts/lib.sh
    . \$APP_DIR/scripts/collectors.sh
    . \$APP_DIR/scripts/discovery.sh
    . \$APP_DIR/scripts/daemon.sh

    load_config '$TMP/mqtt.conf'
    DEVICE_ID=\"\$(device_id)\"
    publish_discovery
    mqtt_publish \"\$(availability_topic \$DEVICE_ID)\" online 0 true

    i=0
    while [ \$i -lt 3 ]; do
        payload=\"\$(build_state_payload \
            '$FIX/power-supply-charging' \
            '$FIX/proc-meminfo' \
            '$FIX/proc-loadavg')\"
        mqtt_publish \"\$(state_topic \$DEVICE_ID)\" \"\$payload\" 0 false
        sleep 1
        i=\$((i+1))
    done

    mqtt_publish \"\$(availability_topic \$DEVICE_ID)\" offline 0 true
" || true

# 5. Stop subscriber, kill broker
sleep 1
kill "$SUB_PID" 2>/dev/null || true
pkill -f "mosquitto -c $TMP/mosquitto.conf" 2>/dev/null || true

# 6. Assertions
fail=0
grep -q 'homeassistant/sensor/miyoo-it_battery/config'   "$TMP/received.log" || { echo "MISS: battery discovery";   fail=1; }
grep -q 'homeassistant/sensor/miyoo-it_volume/config'    "$TMP/received.log" || { echo "MISS: volume discovery";    fail=1; }
grep -q 'homeassistant/sensor/miyoo-it_ram/config'       "$TMP/received.log" || { echo "MISS: ram discovery";       fail=1; }
grep -q 'homeassistant/sensor/miyoo-it_cpu/config'       "$TMP/received.log" || { echo "MISS: cpu discovery";       fail=1; }
grep -q 'homeassistant/binary_sensor/miyoo-it_charging/config' "$TMP/received.log" || { echo "MISS: charging discovery"; fail=1; }
grep -q 'miyoo/miyoo-it/state .*"battery":90'            "$TMP/received.log" || { echo "MISS: state payload";       fail=1; }
grep -q 'miyoo/miyoo-it/availability online'             "$TMP/received.log" || { echo "MISS: availability online"; fail=1; }
grep -q 'miyoo/miyoo-it/availability offline'            "$TMP/received.log" || { echo "MISS: availability offline";fail=1; }

if [ "$fail" -eq 0 ]; then
    echo "Integration test: OK"
    exit 0
else
    echo "Integration test: FAIL"
    echo "--- received.log ---"
    cat "$TMP/received.log"
    exit 1
fi
