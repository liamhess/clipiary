#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_BUNDLE="$ROOT_DIR/dist/Clipiary.app"

"$ROOT_DIR/scripts/build_app.sh" "${1:-debug}"
open "$APP_BUNDLE"
