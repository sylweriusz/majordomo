#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="${1:-${MAJORDOMO_CHANNEL:-stable}}"
case "$CHANNEL" in
stable)
	APP_NAME="Majordomo"
	BUNDLE_ID="pl.wild-matrix.majordomo"
	;;
test)
	APP_NAME="Majordomo Test"
	BUNDLE_ID="pl.wild-matrix.majordomo.test"
	;;
*)
	echo "usage: $0 [stable|test]" >&2
	exit 2
	;;
esac

PRODUCT_NAME="Majordomo"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
ICON_SOURCE="$ROOT_DIR/majordomo.png"

cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$BIN_DIR/$PRODUCT_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ICON_SOURCE" "$RESOURCES_DIR/majordomo.png"

# Copy app-owned helper runtimes. Final runtime must not depend on Homebrew CLIs.
for required_helper in whisper-cli whisper-dictate; do
	if [[ ! -x "$ROOT_DIR/Helpers/$required_helper" ]]; then
		echo "missing required helper: $ROOT_DIR/Helpers/$required_helper" >&2
		exit 1
	fi
done
mkdir -p "$RESOURCES_DIR/Helpers"
cp -R "$ROOT_DIR/Helpers/"* "$RESOURCES_DIR/Helpers/"
# README is documentation, not a runtime artifact — keep it out of the bundle.
rm -f "$RESOURCES_DIR/Helpers/README.md"
find "$RESOURCES_DIR/Helpers" -type f -perm -111 -exec chmod +x {} \;

# Copy SwiftPM resource bundle when present. Bundle.module can resolve it from Contents/Resources.
for RESOURCE_BUNDLE in "$BIN_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.resources" "$BIN_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"; do
	if [[ -d "$RESOURCE_BUNDLE" ]]; then
		cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
	fi
done

# Generate .icns from the provided PNG.
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_NAME.icns"

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Majordomo records microphone audio for local speech-to-text dictation.</string>
</dict>
</plist>
PLIST

# Code signing.
#
# Default (no identity): ad-hoc sign so the bundle carries the correct
# CFBundleIdentifier (the linker otherwise stamps the product name). This is
# safe for local/daily use and does NOT enable hardened runtime, so the
# DYLD_LIBRARY_PATH the app passes to the helpers keeps working.
#
# Distribution: set MAJORDOMO_SIGN_IDENTITY to a "Developer ID Application: …"
# identity to sign helpers + app with hardened runtime, secure timestamp and the
# entitlements files, then notarize and staple (commands printed below).
APP_ENTITLEMENTS="$ROOT_DIR/Majordomo.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/Helpers.entitlements"

if [[ -n "${MAJORDOMO_SIGN_IDENTITY:-}" ]]; then
	echo "[build-app] Developer ID signing with hardened runtime"
	# Sign nested helpers first (inside-out).
	while IFS= read -r -d '' helper; do
		codesign --force --timestamp --options runtime \
			--entitlements "$HELPER_ENTITLEMENTS" \
			--sign "$MAJORDOMO_SIGN_IDENTITY" "$helper"
	done < <(find "$RESOURCES_DIR/Helpers" -type f -perm -111 -print0)
	codesign --force --timestamp --options runtime \
		--entitlements "$APP_ENTITLEMENTS" \
		--identifier "$BUNDLE_ID" \
		--sign "$MAJORDOMO_SIGN_IDENTITY" "$APP_DIR"
	echo "[build-app] signed. To notarize:"
	echo "  ditto -c -k --keepParent \"$APP_DIR\" \"$BUILD_DIR/$APP_NAME.zip\""
	echo "  xcrun notarytool submit \"$BUILD_DIR/$APP_NAME.zip\" --keychain-profile <profile> --wait"
	echo "  xcrun stapler staple \"$APP_DIR\""
else
	# Local ad-hoc signing: fix the bundle identifier only, no hardened runtime.
	codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi

printf 'Built %s (%s)\n' "$APP_DIR" "$BUNDLE_ID"
