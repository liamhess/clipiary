# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clipiary is a macOS clipboard manager with an opt-in global copy-on-select mode. It is a native Swift menu bar application (accessory app) targeting macOS 14+, built with SwiftUI and AppKit. The only external dependency is `swift-snapshot-testing` (Point-Free) for snapshot tests.

## Build & Development Commands

Build the Swift package (isolated module caches):
```sh
/usr/bin/swift build
```

Build an app bundle at `dist/Clipiary.app`:
```sh
python3 tools/clipiary.py build
python3 tools/clipiary.py build --configuration release
```

Run the app bundle:
```sh
python3 tools/clipiary.py run
```

Dev watcher (rebuilds and relaunches on source changes):
```sh
python3 tools/clipiary.py dev
```

Package a release (creates zip, sha256, Homebrew cask):
```sh
python3 tools/clipiary.py release --version <version> [--build-number <build-number>]
```

Start the tag-driven release flow locally:
```sh
python3 tools/clipiary.py start-release patch
python3 tools/clipiary.py start-release minor
python3 tools/clipiary.py start-release major
```

`start-release` stamps `CHANGELOG.md`, commits, pushes to `origin/main`, and pushes the matching tag.

## Changelog

When adding a new user-facing feature or fixing a user-facing bug, add an entry to `CHANGELOG.md` under `## [Unreleased]`. Use `### Added` for new features, `### Fixed` for bug fixes, `### Changed` for behavior changes, `### Removed` for removals. Internal changes (tests, refactoring, CI, tooling) do not need entries.

Run tests (unit + snapshot):
```sh
/usr/bin/swift test
```

Snapshot tests use `swift-snapshot-testing`. On the first run after adding a new snapshot test, the test records a reference image and fails — re-run to assert against it. Reference images live in `Tests/ClipiaryTests/__Snapshots__/` and should be committed.

There is no linter configured in this project.

## Architecture

The SPM package has three targets (Swift tools version 6.2):
- `ClipiaryLib` — library target with all app logic (`Sources/ClipiaryLib/`)
- `ClipiaryApp` — thin executable target with only the `@main` entry point (`Sources/ClipiaryApp/`)
- `ClipiaryTests` — test target with unit and snapshot tests (`Tests/ClipiaryTests/`)

### Layers

**UI** — SwiftUI views hosted in an AppKit `NSPopover`/`NSPanel`:
- `PanelRootView.swift` — root SwiftUI view (History/Favorites tabs, search)
- `HistoryRowView.swift` — individual clipboard item row (extracted for snapshot testing)
- `FloatingPanel.swift` — custom NSPanel for the popover window

**Application State & Lifecycle**:
- `AppDelegate.swift` — NSApplicationDelegate managing lifecycle, keyboard events, popover visibility
- `AppState.swift` — `@Observable` singleton (`AppState.shared`) holding history, favorites, and capture logic
- `AppSettings.swift` — `@Observable` settings backed by UserDefaults

**Capture Engines** (two independent capture paths coordinated together):
- `ClipboardMonitor.swift` — polls `NSPasteboard.general` every 0.4s for clipboard changes
- `CopyOnSelectEngine.swift` — monitors frontmost app and captures text selections via the Accessibility framework
- `CaptureCoordinator.swift` — routes captures from both engines into unified history
- `SelectionReader.swift` — reads text selection using AXUIElement APIs
- `SelectionObserver.swift` — observes AX notifications for selection changes

**System Services**:
- `GlobalHotKeyManager.swift` — registers global keyboard shortcuts via Carbon Event Manager API
- `FrontmostAppMonitor.swift` — tracks the active application
- `AccessibilityPermissionManager.swift` — manages Accessibility (TCC) permission state
- `HistoryStore.swift` — persists/loads clipboard history to disk

### Key Patterns

- `@MainActor` used pervasively for thread safety
- Swift Observation framework (`@Observable`) for reactive state — not Combine
- Carbon `HIToolbox` for global hotkey registration (default: Cmd+Shift+V)
- `AppState.shared` singleton is the central coordination point; an internal `init(settings:history:configManager:permissionManager:)` exists for test injection
- The app is an accessory application (no Dock icon, menu bar only)

## Release Workflow

Tag-driven CI via `.github/workflows/release.yml`. Pushing a `v*` tag on `main` builds, optionally signs with a stable identity, optionally notarizes, creates a GitHub release, and updates the `liamhess/homebrew-tap` cask.

## Environment Variables

Optional `.env` file (loaded automatically by the Python tooling):
- `CLIPIARY_CODESIGN_IDENTITY` — code signing identity (Apple or self-signed)
- `CLIPIARY_BUNDLE_ID` — bundle identifier override
- `CLIPIARY_VERSION` / `CLIPIARY_BUILD_NUMBER` — version overrides

## Testing

Tests live in `Tests/ClipiaryTests/` and import `ClipiaryLib` (via `@testable import`). Use the Swift Testing framework (`import Testing`), not XCTest.

### Writing tests

**Unit tests** (`UnitTests.swift`): Use `makeTestAppState()` and `makeItem(...)` helpers to create isolated `AppState` instances with temp-dir-backed stores and test `UserDefaults` suites. Mark `@MainActor @Suite` for any suite that touches `AppState`, `HistoryStore`, or `AppSettings`.

**Snapshot tests** (`SnapshotTests.swift`): Use `assertSnapshot(of: NSHostingView(rootView: ...), as: .image(size: ...))` to capture SwiftUI views into reference images. `HistoryRowView` is a top-level struct that takes explicit parameters — ideal for snapshot testing in isolation.

### Test-friendly init parameters

- `AppState(settings:history:configManager:permissionManager:)` — creates an instance without starting monitors
- `HistoryStore(storageDirectory:)` — writes to a temp directory instead of Application Support
- `ConfigManager(storageDirectory:)` — same pattern
- `AppSettings(defaults:)` — accepts a test `UserDefaults(suiteName:)` suite
