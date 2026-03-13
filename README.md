# Clipiary

Clipiary is a macOS clipboard manager with an opt-in global autoselect mode.

## Development

Build the Swift package:

```sh
HOME="$PWD/.tmp-home" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift build
```

Build a stable app bundle for Accessibility approval:

```sh
./scripts/build_app.sh
```

Run the app bundle:

```sh
./scripts/run_app.sh
```

Run a dev watcher that rebuilds and relaunches the app on source changes:

```sh
./scripts/dev.sh
```

The app bundle path to approve in `System Settings > Privacy & Security > Accessibility` is:

`dist/Clipiary.app`
