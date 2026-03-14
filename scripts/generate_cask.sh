#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <version> <sha256> [output-path]" >&2
  exit 1
fi

VERSION="$1"
SHA256="$2"
OUTPUT_PATH="${3:-}"
APP_NAME="${CLIPIARY_APP_NAME:-Clipiary}"
CASK_TOKEN="${CLIPIARY_CASK_TOKEN:-clipiary}"
HOMEPAGE="${CLIPIARY_HOMEPAGE:-https://github.com/liamhess/clipiary}"
RELEASE_REPO="${CLIPIARY_RELEASE_REPO:-liamhess/clipiary}"
MACOS_DEPENDS_ON="${CLIPIARY_MACOS_DEPENDS_ON:-sonoma}"
DESCRIPTION="${CLIPIARY_DESCRIPTION:-macOS clipboard manager with an opt-in global autoselect mode}"
ARCHIVE_NAME="${CLIPIARY_ARCHIVE_NAME:-${APP_NAME}-${VERSION}.zip}"
URL="https://github.com/${RELEASE_REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}"

render_cask() {
  cat <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${URL}"
  name "${APP_NAME}"
  desc "${DESCRIPTION}"
  homepage "${HOMEPAGE}"

  depends_on macos: ">= :${MACOS_DEPENDS_ON}"

  app "${APP_NAME}.app"
end
EOF
}

if [[ -n "$OUTPUT_PATH" ]]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  render_cask >"$OUTPUT_PATH"
else
  render_cask
fi
