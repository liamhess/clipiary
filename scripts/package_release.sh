#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <version> [build-number]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/load_env.sh"

VERSION="$1"
BUILD_NUMBER="${2:-${CLIPIARY_BUILD_NUMBER:-1}}"
APP_NAME="${CLIPIARY_APP_NAME:-Clipiary}"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
ARCHIVE_NAME="${CLIPIARY_ARCHIVE_NAME:-${APP_NAME}-${VERSION}.zip}"
ARCHIVE_PATH="$ROOT_DIR/dist/$ARCHIVE_NAME"
NOTARY_ARCHIVE_PATH="$ROOT_DIR/dist/${APP_NAME}-${VERSION}-notarization.zip"
RELEASE_NOTES_PATH="$ROOT_DIR/dist/${APP_NAME}-${VERSION}.release-notes.txt"
SHA256_PATH="$ROOT_DIR/dist/${APP_NAME}-${VERSION}.sha256"
CASK_OUTPUT_PATH="${CLIPIARY_CASK_OUTPUT_PATH:-$ROOT_DIR/dist/${CLIPIARY_CASK_TOKEN:-clipiary}.rb}"
SIGN_IDENTITY="${CLIPIARY_CODESIGN_IDENTITY:-}"
NOTARY_APPLE_ID="${CLIPIARY_NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${CLIPIARY_NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${CLIPIARY_NOTARY_PASSWORD:-}"

mkdir -p "$ROOT_DIR/dist"
rm -f "$ARCHIVE_PATH" "$NOTARY_ARCHIVE_PATH" "$SHA256_PATH" "$RELEASE_NOTES_PATH"

export CLIPIARY_VERSION="$VERSION"
export CLIPIARY_BUILD_NUMBER="$BUILD_NUMBER"

if [[ -n "$SIGN_IDENTITY" ]]; then
  export CLIPIARY_CODESIGN_FLAGS="${CLIPIARY_CODESIGN_FLAGS:---timestamp --options runtime}"
fi

"$ROOT_DIR/scripts/build_app.sh" release

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle at $APP_BUNDLE" >&2
  exit 1
fi

zip_app() {
  local source_bundle="$1"
  local output_path="$2"
  ditto -c -k --keepParent --sequesterRsrc "$source_bundle" "$output_path"
}

if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_PASSWORD" ]]; then
  zip_app "$APP_BUNDLE" "$NOTARY_ARCHIVE_PATH"
  xcrun notarytool submit "$NOTARY_ARCHIVE_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$NOTARY_ARCHIVE_PATH"
fi

zip_app "$APP_BUNDLE" "$ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}' >"$SHA256_PATH"
SHA256="$(cat "$SHA256_PATH")"

"$ROOT_DIR/scripts/generate_cask.sh" "$VERSION" "$SHA256" "$CASK_OUTPUT_PATH"

cat >"$RELEASE_NOTES_PATH" <<EOF
Version: $VERSION
Build: $BUILD_NUMBER
Archive: $ARCHIVE_PATH
SHA256: $SHA256
Cask: $CASK_OUTPUT_PATH
EOF

echo "version=$VERSION"
echo "build_number=$BUILD_NUMBER"
echo "archive_path=$ARCHIVE_PATH"
echo "sha256=$SHA256"
echo "sha256_path=$SHA256_PATH"
echo "cask_path=$CASK_OUTPUT_PATH"
echo "release_notes_path=$RELEASE_NOTES_PATH"
