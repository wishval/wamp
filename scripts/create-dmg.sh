#!/bin/bash
# Package Wamp.app into a compressed DMG with an /Applications shortcut.
#
# Usage: scripts/create-dmg.sh <version> [path/to/Wamp.app]
#
#   version   — goes into the file name: release/Wamp-<version>-macOS-arm64.dmg
#   app path  — defaults to the Release product under .build/DerivedData
#               (what `xcodebuild ... -derivedDataPath .build/DerivedData` writes)
#
# Deliberately plain: no Finder/AppleScript window layout, so it runs the
# same on a headless CI runner and on a developer machine.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wamp"

VERSION="${1:?Usage: scripts/create-dmg.sh <version> [path/to/Wamp.app]}"
APP="${2:-$PROJECT_DIR/.build/DerivedData/Build/Products/Release/$APP_NAME.app}"

if [ ! -d "$APP" ]; then
  echo "error: app bundle not found: $APP" >&2
  echo "       build it first, e.g.:" >&2
  echo "       xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Release \\" >&2
  echo "         -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData build" >&2
  exit 1
fi

ARCH="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null | tr ' ' '-')"
ARCH="${ARCH:-arm64}"

RELEASE_DIR="$PROJECT_DIR/release"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-macOS-${ARCH}.dmg"

STAGING="$(mktemp -d -t wamp-dmg)"
trap 'rm -rf "$STAGING"' EXIT

echo "Staging $APP"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null

hdiutil verify "$DMG_PATH" >/dev/null

echo "OK  $DMG_PATH  ($(du -h "$DMG_PATH" | cut -f1))"
