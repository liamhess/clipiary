# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clipiary is a macOS clipboard manager with an opt-in global copy-on-select mode. It is a native Swift menu bar application (accessory app) targeting macOS 14+, built with SwiftUI and AppKit. There are no external dependencies — everything uses macOS SDK frameworks.

## Build & Development Commands

Build the Swift package (isolated module caches):
```sh
swift build
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

There are no tests or linter configured in this project.

## Architecture

All source code lives in `Sources/ClipiaryApp/` (single SPM executable target, Swift tools version 6.2).

### Layers

**UI** — SwiftUI views hosted in an AppKit `NSPopover`/`NSPanel`:
- `PanelRootView.swift` — root SwiftUI view (History/Favorites tabs, search)
- `FloatingPanel.swift` — custom NSPanel for the popover window
- `PopoverHostingController.swift` — bridges SwiftUI into NSPopover

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
- `AppState.shared` singleton is the central coordination point
- The app is an accessory application (no Dock icon, menu bar only)

## Release Workflow

Tag-driven CI via `.github/workflows/release.yml`. Pushing a `v*` tag on `main` builds, optionally signs with a stable identity, optionally notarizes, creates a GitHub release, and updates the `liamhess/homebrew-tap` cask.

## Environment Variables

Optional `.env` file (loaded automatically by the Python tooling):
- `CLIPIARY_CODESIGN_IDENTITY` — code signing identity (Apple or self-signed)
- `CLIPIARY_BUNDLE_ID` — bundle identifier override
- `CLIPIARY_VERSION` / `CLIPIARY_BUILD_NUMBER` — version overrides
