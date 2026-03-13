#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="Clipiary"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
WATCH_INTERVAL="${WATCH_INTERVAL:-1}"
TMP_HOME="$ROOT_DIR/.tmp-home"
MODULE_CACHE="$ROOT_DIR/.build/module-cache"
CLANG_CACHE="$ROOT_DIR/.build/clang-module-cache"

watch_paths=(
  "$ROOT_DIR/Package.swift"
  "$ROOT_DIR/Sources"
  "$ROOT_DIR/scripts"
)

export HOME="$TMP_HOME"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE"

mkdir -p "$TMP_HOME" "$MODULE_CACHE" "$CLANG_CACHE"

build_and_restart() {
  echo "==> Building Clipiary"
  "$ROOT_DIR/scripts/build_app.sh"

  echo "==> Restarting Clipiary"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  open "$APP_BUNDLE"
}

snapshot() {
  find "${watch_paths[@]}" \
    \( -name "*.swift" -o -name "*.sh" -o -name "Package.swift" \) \
    -type f \
    -print0 |
    xargs -0 stat -f "%m %N" |
    sort |
    shasum -a 256 |
    awk '{print $1}'
}

watch_with_fswatch() {
  echo "==> Watching with fswatch"
  fswatch -0 "${watch_paths[@]}" | while IFS= read -r -d '' _event; do
    sleep 0.2
    build_and_restart
  done
}

watch_with_polling() {
  echo "==> Watching with polling every ${WATCH_INTERVAL}s"
  local last_snapshot
  last_snapshot="$(snapshot)"

  while true; do
    sleep "$WATCH_INTERVAL"
    local next_snapshot
    next_snapshot="$(snapshot)"
    if [[ "$next_snapshot" != "$last_snapshot" ]]; then
      last_snapshot="$next_snapshot"
      build_and_restart
    fi
  done
}

cleanup() {
  echo
  echo "==> Stopping dev watcher"
}

trap cleanup INT TERM

build_and_restart

if command -v fswatch >/dev/null 2>&1; then
  watch_with_fswatch
else
  watch_with_polling
fi
