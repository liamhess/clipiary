import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusSyncTimer: Timer?
    private var localKeyMonitor: Any?
    private let popover = NSPopover()
    private let hotKeyManager = GlobalHotKeyManager()
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipiary")
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        return item
    }()

    private let appState = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        appState.start()
        configurePopover()
        configureHotKey()
        configureKeyMonitor()
        updateStatusItem()
        statusSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
        return true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isAutoSelectEnabled
        button.appearsDisabled = isPaused
        button.title = ""
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 376, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: PanelRootView()
                .environment(appState)
        )
    }

    private func configureHotKey() {
        hotKeyManager.onTrigger = { [weak self] in
            self?.togglePopover()
        }
        registerHotKey()
        synchronizeHotKeyRegistration()
    }

    private func registerHotKey() {
        hotKeyManager.register(shortcut: appState.settings.globalShortcut)
    }

    private func synchronizeHotKeyRegistration() {
        _ = withObservationTracking {
            (appState.settings.globalHotKeyKeyCode, appState.settings.globalHotKeyModifiers)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.registerHotKey()
                self?.synchronizeHotKeyRegistration()
            }
        }
    }

    private func configureKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event) ?? event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else {
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let normalizedCharacters = event.charactersIgnoringModifiers?.lowercased()

        if appState.isRecordingShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingShortcut = false
            default:
                appState.updateGlobalShortcut(from: event)
            }
            return nil
        }

        if modifiers == .command,
           normalizedCharacters == "f" {
            appState.requestSearchFocus()
            return nil
        }

        if modifiers == [.command, .shift],
           normalizedCharacters == "f" {
            appState.toggleFavoriteSelectedItem()
            return nil
        }

        if !modifiers.isDisjoint(with: [.command, .option, .control]) {
            return event
        }

        switch event.keyCode {
        case 123:
            appState.moveTab(direction: -1)
            return nil
        case 124:
            appState.moveTab(direction: 1)
            return nil
        case 125:
            appState.moveSelection(direction: 1)
            return nil
        case 126:
            appState.moveSelection(direction: -1)
            return nil
        case 36:
            appState.restoreSelectedItem()
            return nil
        case 51:
            appState.deleteSelectedItem()
            return nil
        case 53:
            popover.performClose(nil)
            return nil
        default:
            return event
        }
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            button.isHighlighted = true
            appState.didOpenPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.isHighlighted = false
        appState.isRecordingShortcut = false
    }
}
