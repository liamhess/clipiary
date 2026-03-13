#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/load_env.sh"
CONFIGURATION="${1:-debug}"
APP_NAME="Clipiary"
BUNDLE_ID="dev.liamhess.clipiary"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
TMP_HOME="$ROOT_DIR/.tmp-home"
MODULE_CACHE="$ROOT_DIR/.build/module-cache"
CLANG_CACHE="$ROOT_DIR/.build/clang-module-cache"
CODESIGN_IDENTITY="${CLIPIARY_CODESIGN_IDENTITY:-}"

mkdir -p "$TMP_HOME" "$MODULE_CACHE" "$CLANG_CACHE" "$MACOS_DIR" "$RESOURCES_DIR"

swift_build() {
  HOME="$TMP_HOME" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
  swift build "$@"
}

swift_build --configuration "$CONFIGURATION"
BIN_DIR="$(swift_build --configuration "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Built executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -f "$MACOS_DIR/$APP_NAME"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$CONTENTS_DIR/Info.plist"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
  echo "Signed app bundle with identity: $CODESIGN_IDENTITY"
else
  codesign --remove-signature "$APP_BUNDLE" 2>/dev/null || true
  echo "Built app bundle without code signing."
  echo "Tip: set CLIPIARY_CODESIGN_IDENTITY to a stable signing identity to preserve TCC permissions."
fi

echo "Built app bundle:"
echo "$APP_BUNDLE"
