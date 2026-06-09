#!/usr/bin/env bash
# Build a release zip, publish it into the website folder, and update the
# Homebrew cask with the new version + checksum.
#
# Flow:
#   1. build the stable .app
#   2. zip it (ditto, bundle-safe) into web_page/ so a Cloudflare Pages deploy
#      publishes it at https://majordomo.pomr.uk/Majordomo-macOS.zip
#   3. compute sha256
#   4. rewrite version + sha256 in Casks/majordomo.rb
#
# Then: deploy web_page/ to Cloudflare and push Casks/majordomo.rb to the
# public homebrew-majordomo tap repo. See docs/DISTRIBUTION.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP="build/Majordomo.app"
ZIP="web_page/Majordomo-macOS.zip"
CASK="Casks/majordomo.rb"

echo "[release] building stable .app"
scripts/build-app.sh stable >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ -z "$VERSION" ]]; then
	echo "[release] could not read CFBundleShortVersionString" >&2
	exit 1
fi

echo "[release] zipping $APP -> $ZIP"
rm -f "$ZIP"
# ditto keeps the bundle layout, symlinks and code signature intact.
ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo "[release] updating $CASK"
# Rewrite the managed version/sha256 lines in the cask.
V="$VERSION" perl -pi -e 's/^  version ".*"/  version "$ENV{V}"/' "$CASK"
S="$SHA" perl -pi -e 's/^  sha256 ".*"/  sha256 "$ENV{S}"/' "$CASK"

echo ""
echo "Released Majordomo $VERSION"
echo "  zip:    $ZIP ($(du -h "$ZIP" | awk '{print $1}'))"
echo "  sha256: $SHA"
echo ""
echo "Next steps:"
echo "  1. Deploy web_page/ to Cloudflare Pages (publishes the new zip)."
echo "  2. Copy $CASK into the homebrew-majordomo tap repo and push:"
echo "       cp $CASK <tap-repo>/Casks/majordomo.rb && (cd <tap-repo> && git commit -am \"majordomo $VERSION\" && git push)"
