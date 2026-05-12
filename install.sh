#!/bin/sh
# shellcheck shell=sh
# Usage: ./install.sh <SD_MOUNT>
# Example: ./install.sh /Volumes/MIYOO
set -eu

SD="${1:-}"
if [ -z "$SD" ] || [ ! -d "$SD" ]; then
    echo "Usage: $0 <SD_MOUNT>"
    echo "  e.g.  $0 /Volumes/MIYOO"
    exit 2
fi
if [ ! -d "$SD/.tmp_update" ]; then
    echo "ERROR: $SD does not look like an OnionOS SD card (no .tmp_update)."
    exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing App to $SD/App/MQTTReporter ..."
mkdir -p "$SD/App/MQTTReporter"
# rsync if available, else cp -R
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
        --exclude '.gitkeep' \
        "$REPO_DIR/App/MQTTReporter/" "$SD/App/MQTTReporter/"
else
    rm -rf "$SD/App/MQTTReporter"
    cp -R "$REPO_DIR/App/MQTTReporter" "$SD/App/"
    find "$SD/App/MQTTReporter" -name .gitkeep -delete
fi

echo "Installing boot hook to $SD/.tmp_update/runtime.sh.user ..."
# Preserve existing hook content if user already has one.
if [ -e "$SD/.tmp_update/runtime.sh.user" ] && \
   ! grep -q 'MQTTReporter' "$SD/.tmp_update/runtime.sh.user"; then
    echo "  Existing runtime.sh.user found — appending our block."
    {
        echo ""
        echo "# --- MQTTReporter (auto-added) ---"
        grep -v '^#!/bin/sh' "$REPO_DIR/boot/runtime.sh.user"
    } >> "$SD/.tmp_update/runtime.sh.user"
else
    cp "$REPO_DIR/boot/runtime.sh.user" "$SD/.tmp_update/runtime.sh.user"
fi
chmod +x "$SD/.tmp_update/runtime.sh.user"

echo "Ensuring scripts are executable ..."
chmod +x "$SD/App/MQTTReporter/launch.sh" \
         "$SD/App/MQTTReporter/scripts/"*.sh \
         "$SD/App/MQTTReporter/bin/mosquitto_pub"

echo
echo "Done. Next steps on device:"
echo "  1. Boot the Miyoo."
echo "  2. Open Apps -> MQTT Reporter once (creates etc/mqtt.conf)."
echo "  3. SSH or pull SD: edit /mnt/SDCARD/App/MQTTReporter/etc/mqtt.conf"
echo "     to set MQTT_HOST/USER/PASS."
echo "  4. Reopen the app to toggle ON, or reboot — it autostarts."
