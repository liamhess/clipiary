#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/load_env.sh"
APP_NAME="Clipiary"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
WATCH_INTERVAL="${WATCH_INTERVAL:-1}"
APP_PID=""

watch_paths=(
  "$ROOT_DIR/Package.swift"
  "$ROOT_DIR/Sources"
  "$ROOT_DIR/scripts"
)

build_and_restart() {
  echo "==> Building Clipiary"
  "$ROOT_DIR/scripts/build_app.sh"

  echo "==> Restarting Clipiary"
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  else
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
  sleep 0.2
  "$APP_EXECUTABLE" >/tmp/clipiary-dev.log 2>&1 &
  APP_PID=$!
}

snapshot() {
  local stat_fmt
  if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
    stat_fmt=(stat -f "%m %N")   # BSD stat (macOS default)
  else
    stat_fmt=(stat -c "%Y %n")   # GNU stat (coreutils)
  fi

  find "${watch_paths[@]}" \
    \( -name "*.swift" -o -name "*.sh" -o -name "Package.swift" \) \
    -type f \
    -print0 |
    xargs -0 "${stat_fmt[@]}" |
    sort |
    shasum -a 256 |
    awk '{print $1}'
}

watch_with_fswatch() {
  echo "==> Watching with fswatch"
  fswatch -o --latency 0.4 "${watch_paths[@]}" | while read -r _batch_count; do
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
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "==> Stopping Clipiary"
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  echo "==> Stopping dev watcher"
}

trap cleanup INT TERM

build_and_restart

if command -v fswatch >/dev/null 2>&1; then
  watch_with_fswatch
else
  watch_with_polling
fi
