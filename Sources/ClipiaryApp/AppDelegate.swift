import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusSyncTimer: Timer?
    private var localKeyMonitor: Any?
    private var suppressedKeyUps = Set<UInt16>()
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
        configureCommandMenu()
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

    func applicationDidResignActive(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isAutoSelectEnabled
        button.appearsDisabled = isPaused
        button.title = ""
    }

    private func configureCommandMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Clipiary")

        let focusSearchItem = NSMenuItem(
            title: "Focus Search",
            action: #selector(focusSearchCommand),
            keyEquivalent: "f"
        )
        focusSearchItem.keyEquivalentModifierMask = [.command]
        focusSearchItem.target = self
        appMenu.addItem(focusSearchItem)

        let toggleFavoriteItem = NSMenuItem(
            title: "Toggle Favorite",
            action: #selector(toggleFavoriteCommand),
            keyEquivalent: "d"
        )
        toggleFavoriteItem.keyEquivalentModifierMask = [.command]
        toggleFavoriteItem.target = self
        appMenu.addItem(toggleFavoriteItem)

        let closePopoverItem = NSMenuItem(
            title: "Close Popover",
            action: #selector(closePopoverCommand),
            keyEquivalent: "\u{1b}"
        )
        closePopoverItem.target = self
        appMenu.addItem(closePopoverItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clipiary",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 376, height: 600)
        popover.contentViewController = PopoverHostingController(
            appState: appState,
            onClose: { [weak self] in
                self?.closePopoverCommand()
            }
        )
    }

    private func configureHotKey() {
        hotKeyManager.onTrigger = { [weak self] in
            self?.togglePopover()
        }
        synchronizeHotKeyRegistration()
    }

    private func synchronizeHotKeyRegistration() {
        updateHotKeyRegistration()
        observeHotKeyRegistrationDependencies()
    }

    private func updateHotKeyRegistration() {
        if appState.isRecordingShortcut {
            hotKeyManager.unregister()
        } else {
            hotKeyManager.register(shortcut: appState.settings.globalShortcut)
        }
    }

    private func observeHotKeyRegistrationDependencies() {
        _ = withObservationTracking {
            (
                appState.settings.globalHotKeyKeyCode,
                appState.settings.globalHotKeyModifiers,
                appState.isRecordingShortcut
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateHotKeyRegistration()
                self?.observeHotKeyRegistrationDependencies()
            }
        }
    }

    private func configureKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleMonitoredEvent(event) ?? event
        }
    }

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        if shouldSuppressKeyUp(event) {
            return nil
        }

        guard event.type == .keyDown else {
            return event
        }

        return handleKeyDownEvent(event)
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else {
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if appState.isRecordingShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingShortcut = false
            default:
                appState.updateGlobalShortcut(from: event)
            }
            return suppressKeyUp(for: event)
        }

        if !modifiers.isDisjoint(with: [.command, .option, .control]) {
            return event
        }

        switch event.keyCode {
        case 123:
            appState.moveTab(direction: -1)
            return suppressKeyUp(for: event)
        case 124:
            appState.moveTab(direction: 1)
            return suppressKeyUp(for: event)
        case 125:
            appState.moveSelection(direction: 1)
            return suppressKeyUp(for: event)
        case 126:
            appState.moveSelection(direction: -1)
            return suppressKeyUp(for: event)
        case 36:
            appState.restoreSelectedItem()
            return suppressKeyUp(for: event)
        case 51:
            appState.deleteSelectedItem()
            return suppressKeyUp(for: event)
        default:
            return event
        }
    }

    private func shouldSuppressKeyUp(_ event: NSEvent) -> Bool {
        guard popover.isShown, event.type == .keyUp else {
            return false
        }

        if suppressedKeyUps.contains(event.keyCode) {
            suppressedKeyUps.remove(event.keyCode)
            return true
        }

        return false
    }

    private func suppressKeyUp(for event: NSEvent) -> NSEvent? {
        suppressedKeyUps.insert(event.keyCode)
        return nil
    }

    @objc
    private func focusSearchCommand() {
        if !popover.isShown {
            togglePopover()
        }

        appState.requestSearchFocus()
    }

    @objc
    private func toggleFavoriteCommand() {
        guard popover.isShown else {
            return
        }

        appState.toggleFavoriteSelectedItem()
    }

    @objc
    private func closePopoverCommand() {
        guard popover.isShown else {
            return
        }

        popover.performClose(nil)
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            button.isHighlighted = true
            appState.didOpenPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                self?.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.isHighlighted = false
        appState.isRecordingShortcut = false
        suppressedKeyUps.removeAll()
    }
}
