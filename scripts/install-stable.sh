#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Majordomo"
BUNDLE_ID="pl.wild-matrix.majordomo"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_SOURCE="$ROOT_DIR/build/$APP_NAME.app"
APP_TARGET="$INSTALL_DIR/$APP_NAME.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/$BUNDLE_ID.plist"

cd "$ROOT_DIR"
./scripts/build-app.sh stable

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_TARGET"
cp -R "$APP_SOURCE" "$APP_TARGET"

if [[ "${ENABLE_LAUNCH_AT_LOGIN:-1}" == "1" ]]; then
	mkdir -p "$LAUNCH_AGENT_DIR"
	cat >"$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP_TARGET</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST
	launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
	launchctl load "$LAUNCH_AGENT"
fi

open "$APP_TARGET"

echo "Installed stable $APP_NAME: $APP_TARGET"
if [[ "${ENABLE_LAUNCH_AT_LOGIN:-1}" == "1" ]]; then
	echo "Launch at login enabled: $LAUNCH_AGENT"
fi
