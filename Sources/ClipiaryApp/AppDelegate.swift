import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusSyncTimer: Timer?
    private var localKeyMonitor: Any?
    private var suppressedKeyUps = Set<UInt16>()
    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?
    private let hotKeyManager = GlobalHotKeyManager(id: 1)
    private let quickPasteHotKeyManager = GlobalHotKeyManager(id: 2)
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

    private var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        appState.start()
        configureCommandMenu()
        configurePanel()
        configureHotKey()
        configureKeyMonitor()
        observePasteRequests()
        observeQuickPasteRequests()
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
        if isPanelVisible {
            panel?.close()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isCopyOnSelectEnabled
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

    private func configurePanel() {
        let panel = FloatingPanel(
            statusBarButton: statusItem.button,
            appState: appState
        )
        panel.onClose = { [weak self] in
            self?.panelDidClose()
        }
        self.panel = panel
    }

    private func configureHotKey() {
        hotKeyManager.onTrigger = { [weak self] in
            self?.togglePopover()
        }
        quickPasteHotKeyManager.onTrigger = { [weak self] in
            self?.appState.requestQuickPaste()
        }
        synchronizeHotKeyRegistration()
    }

    private func synchronizeHotKeyRegistration() {
        updateHotKeyRegistration()
        observeHotKeyRegistrationDependencies()
    }

    private func updateHotKeyRegistration() {
        let anyRecording = appState.isRecordingShortcut || appState.isRecordingQuickPasteShortcut
        if anyRecording {
            hotKeyManager.unregister()
            quickPasteHotKeyManager.unregister()
        } else {
            hotKeyManager.register(shortcut: appState.settings.globalShortcut)
            quickPasteHotKeyManager.register(shortcut: appState.settings.quickPasteShortcut)
        }
    }

    private func observeHotKeyRegistrationDependencies() {
        _ = withObservationTracking {
            (
                appState.settings.globalHotKeyKeyCode,
                appState.settings.globalHotKeyModifiers,
                appState.settings.quickPasteHotKeyKeyCode,
                appState.settings.quickPasteHotKeyModifiers,
                appState.isRecordingShortcut,
                appState.isRecordingQuickPasteShortcut
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
        guard isPanelVisible else {
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

        if appState.isRecordingQuickPasteShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingQuickPasteShortcut = false
            default:
                appState.updateQuickPasteShortcut(from: event)
            }
            return suppressKeyUp(for: event)
        }

        if !modifiers.isDisjoint(with: [.command, .option, .control]) {
            return event
        }

        if appState.showingFavoriteTabPicker {
            switch event.keyCode {
            case 125: // Down
                appState.movePickerSelection(direction: 1)
                return suppressKeyUp(for: event)
            case 126: // Up
                appState.movePickerSelection(direction: -1)
                return suppressKeyUp(for: event)
            case 36, 49: // Return, Space
                appState.confirmPickerSelection()
                return suppressKeyUp(for: event)
            default:
                return event
            }
        }

        switch event.keyCode {
        case 49:
            guard appState.searchQuery.isEmpty else { return event }
            appState.togglePreview()
            return suppressKeyUp(for: event)
        case 123:
            guard appState.searchQuery.isEmpty else { return event }
            appState.moveTab(direction: -1)
            return suppressKeyUp(for: event)
        case 124:
            guard appState.searchQuery.isEmpty else { return event }
            appState.moveTab(direction: 1)
            return suppressKeyUp(for: event)
        case 125:
            appState.moveSelection(direction: 1)
            return suppressKeyUp(for: event)
        case 126:
            appState.moveSelection(direction: -1)
            return suppressKeyUp(for: event)
        case 36:
            appState.requestPasteSelected()
            return suppressKeyUp(for: event)
        case 117:
            appState.deleteSelectedItem()
            return suppressKeyUp(for: event)
        default:
            return event
        }
    }

    private func shouldSuppressKeyUp(_ event: NSEvent) -> Bool {
        guard event.type == .keyUp else {
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
        if !isPanelVisible {
            togglePopover()
        }

        appState.requestSearchFocus()
    }

    @objc
    private func toggleFavoriteCommand() {
        guard isPanelVisible else {
            return
        }

        appState.toggleFavoriteSelectedItem()
    }

    @objc
    private func closePopoverCommand() {
        guard isPanelVisible else {
            return
        }

        panel?.close()
    }

    @objc
    private func togglePopover() {
        guard let panel else {
            return
        }

        if panel.isVisible {
            panel.close()
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            appState.didOpenPopover()
            panel.open()
        }
    }

    private func panelDidClose() {
        statusItem.button?.isHighlighted = false
        appState.isRecordingShortcut = false
        appState.isRecordingQuickPasteShortcut = false
        appState.showingFavoriteTabPicker = false
        appState.searchQuery = ""
        suppressedKeyUps.removeAll()
        let targetApp = previousApp
        previousApp = nil
        targetApp?.activate()
    }

    private func observePasteRequests() {
        _ = withObservationTracking {
            appState.pasteSelectedRequestID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.pasteSelectedAndClose()
                self?.observePasteRequests()
            }
        }
    }

    private func observeQuickPasteRequests() {
        _ = withObservationTracking {
            appState.quickPasteRequestID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.quickPaste()
                self?.observeQuickPasteRequests()
            }
        }
    }

    private func quickPaste() {
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.postPaste()
        }
    }

    private func pasteSelectedAndClose() {
        guard isPanelVisible else {
            return
        }
        let canPaste = AXIsProcessTrusted()
        panel?.close()
        let targetApp = previousApp
        previousApp = nil
        targetApp?.activate()
        if canPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Self.postPaste()
            }
        }
    }

    private nonisolated static func postPaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let vKey: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
