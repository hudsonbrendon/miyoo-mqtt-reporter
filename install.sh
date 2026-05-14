#!/bin/sh
# shellcheck shell=sh
# Usage: ./install.sh <SD_MOUNT>
# Example: ./install.sh /Volumes/Onion
set -eu

SD="${1:-}"
if [ -z "$SD" ] || [ ! -d "$SD" ]; then
    echo "Usage: $0 <SD_MOUNT>"
    echo "  e.g.  $0 /Volumes/Onion"
    exit 2
fi
if [ ! -d "$SD/.tmp_update" ]; then
    echo "ERROR: $SD does not look like an OnionOS SD card (no .tmp_update)."
    exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing App to $SD/App/MQTTReporter ..."
mkdir -p "$SD/App/MQTTReporter"
if command -v rsync >/dev/null 2>&1; then
    # Force-copy symlinks as real files — FAT32 doesn't preserve POSIX symlinks
    # and Linux on the Miyoo would read the link target text as garbage ELF.
    rsync -aL --delete \
        --exclude '.gitkeep' \
        --exclude '/etc/mqtt.conf' \
        "$REPO_DIR/App/MQTTReporter/" "$SD/App/MQTTReporter/"
else
    rm -rf "$SD/App/MQTTReporter"
    cp -RL "$REPO_DIR/App/MQTTReporter" "$SD/App/"
    find "$SD/App/MQTTReporter" -name .gitkeep -delete
fi

echo "Installing OnionOS startup hook to $SD/.tmp_update/startup/mqttreporter.sh ..."
mkdir -p "$SD/.tmp_update/startup"
cp "$REPO_DIR/boot/startup/mqttreporter.sh" "$SD/.tmp_update/startup/mqttreporter.sh"
chmod +x "$SD/.tmp_update/startup/mqttreporter.sh"

# Migration: remove the obsolete runtime.sh.user hook from older releases.
if [ -e "$SD/.tmp_update/runtime.sh.user" ] && \
   grep -q 'MQTTReporter' "$SD/.tmp_update/runtime.sh.user" 2>/dev/null; then
    echo "  Removing obsolete runtime.sh.user MQTTReporter block (OnionOS does not exec it)..."
    rm -f "$SD/.tmp_update/runtime.sh.user"
fi

echo "Ensuring scripts are executable ..."
chmod +x "$SD/App/MQTTReporter/launch.sh" \
         "$SD/App/MQTTReporter/scripts/"*.sh \
         "$SD/App/MQTTReporter/bin/mosquitto_pub"
if [ -d "$SD/App/MQTTReporter/www/cgi-bin" ]; then
    chmod +x "$SD/App/MQTTReporter/www/cgi-bin/"* 2>/dev/null || true
fi

# Cleanup macOS metadata cruft if installing from a Mac onto FAT32.
find "$SD/App/MQTTReporter" -name '._*' -delete 2>/dev/null || true
find "$SD/.tmp_update/startup" -name '._*' -delete 2>/dev/null || true

# Enable autostart by default (presence of state/enabled).
mkdir -p "$SD/App/MQTTReporter/state"
touch "$SD/App/MQTTReporter/state/enabled"

echo
echo "Done. Next steps:"
echo "  1. (optional) Pre-edit $SD/App/MQTTReporter/etc/mqtt.conf"
echo "     or skip this — you can configure broker/user/pass from the web UI."
echo "  2. Eject the SD card, slot it into the Miyoo, boot."
echo "  3. Open the MQTT Reporter app from the Apps menu: it shows the device"
echo "     IP and the URL of the on-device config UI (e.g. http://<ip>:8088)."
echo "  4. From any phone on the same Wi-Fi, open that URL, fill the broker"
echo "     details, hit Save. The daemon restarts and starts publishing."
echo "  5. Confirm in Home Assistant: Settings → Devices → MQTT."
