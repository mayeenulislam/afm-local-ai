#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AFM Local AI"
VERSION="$("$ROOT_DIR/scripts/version.sh")"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME $VERSION.dmg"

echo "Version: $VERSION"

"$ROOT_DIR/scripts/build_dev.sh"

PLIST="$APP_DIR/Contents/Info.plist"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "Stamped $VERSION (build $BUILD_NUMBER) into $PLIST"

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$APP_DIR"
  echo "Signed with $DEVELOPER_ID_IDENTITY"
else
  codesign --force --sign - "$APP_DIR"
  echo "Ad-hoc signed (Gatekeeper will still warn; set DEVELOPER_ID_IDENTITY for notarization-ready signing)"
fi
codesign --verify --strict "$APP_DIR"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Built $DMG_PATH"