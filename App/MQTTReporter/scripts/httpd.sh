#!/bin/sh
# Bring up busybox's built-in HTTP server to host the on-device config UI.
# Single-process foreground (`-f`), the startup hook nohups it.
# shellcheck shell=sh
set -u

APP_DIR="${APP_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
WWW_DIR="$APP_DIR/www"
STATE_DIR="${STATE_DIR:-$APP_DIR/state}"
PORT="${HTTPD_PORT:-8088}"

mkdir -p "$STATE_DIR"

# Export APP_DIR so the CGI scripts know where the conf and helpers live.
export APP_DIR

# Sanity checks — fail loudly to the daemon log so the user sees what's wrong.
if [ ! -d "$WWW_DIR" ]; then
    echo "[httpd] missing www dir at $WWW_DIR" >&2
    exit 1
fi
if ! command -v busybox >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1; then
    echo "[httpd] no busybox or httpd binary found; web UI disabled" >&2
    exit 1
fi

# Make the CGI scripts executable each boot — FAT32 can lose the +x bit.
chmod +x "$WWW_DIR/cgi-bin/"* 2>/dev/null || true

# Resolve the httpd applet name.
if command -v busybox >/dev/null 2>&1; then
    HTTPD="busybox httpd"
else
    HTTPD="httpd"
fi

# -f foreground, -p port, -h docroot
# busybox httpd auto-runs anything under <docroot>/cgi-bin/ as CGI.
echo "[httpd] starting on :$PORT docroot=$WWW_DIR"
exec $HTTPD -f -p "$PORT" -h "$WWW_DIR"
