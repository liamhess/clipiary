import AppKit
import Observation
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusSyncTimer: Timer?
    private var localKeyMonitor: Any?
    private var suppressedKeyUps = Set<UInt16>()
    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?
    private let hotKeyManager = GlobalHotKeyManager(id: 1)
    private let quickPasteHotKeyManager = GlobalHotKeyManager(id: 2)
    private let globalAltPasteHotKeyManager = GlobalHotKeyManager(id: 3)
    private var itemHotKeyManagers: [UUID: GlobalHotKeyManager] = [:]
    private var nextItemHotKeyID: UInt32 = 10
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipiary")
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }()

    private let appState = AppState.shared
    private let updaterManager = UpdaterManager.shared

    override public init() {
        super.init()
    }

    private var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(200, forKey: "NSInitialToolTipDelay")
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

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
        return true
    }

    public func applicationDidResignActive(_ notification: Notification) {
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

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

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
        globalAltPasteHotKeyManager.onTrigger = { [weak self] in
            self?.appState.requestGlobalAltPaste()
        }
        synchronizeHotKeyRegistration()
    }

    private func synchronizeHotKeyRegistration() {
        updateHotKeyRegistration()
        observeHotKeyRegistrationDependencies()
    }

    private func updateHotKeyRegistration() {
        let anyRecording = appState.isRecordingShortcut || appState.isRecordingQuickPasteShortcut || appState.isRecordingLocalAltPasteShortcut || appState.isRecordingGlobalAltPasteShortcut || appState.isRecordingItemShortcut
        if anyRecording {
            hotKeyManager.unregister()
            quickPasteHotKeyManager.unregister()
            globalAltPasteHotKeyManager.unregister()
            for (_, mgr) in itemHotKeyManagers { mgr.unregister() }
        } else {
            hotKeyManager.register(shortcut: appState.settings.globalShortcut)
            quickPasteHotKeyManager.register(shortcut: appState.settings.quickPasteShortcut)
            globalAltPasteHotKeyManager.register(shortcut: appState.settings.globalAltPasteShortcut)
            rebuildItemHotKeys()
        }
    }

    private func rebuildItemHotKeys() {
        for (_, manager) in itemHotKeyManagers {
            manager.unregister()
        }
        itemHotKeyManagers.removeAll()

        for item in appState.history.items {
            guard let shortcut = item.globalShortcut else { continue }
            let id = nextItemHotKeyID
            nextItemHotKeyID += 1
            let manager = GlobalHotKeyManager(id: id)
            let itemID = item.id
            manager.onTrigger = { [weak self] in
                self?.appState.requestItemPaste(itemID: itemID)
            }
            manager.register(shortcut: shortcut)
            itemHotKeyManagers[item.id] = manager
        }
    }

    private func observeHotKeyRegistrationDependencies() {
        _ = withObservationTracking {
            (
                appState.settings.globalHotKeyKeyCode,
                appState.settings.globalHotKeyModifiers,
                appState.settings.quickPasteHotKeyKeyCode,
                appState.settings.quickPasteHotKeyModifiers,
                appState.settings.globalAltPasteHotKeyKeyCode,
                appState.settings.globalAltPasteHotKeyModifiers,
                appState.isRecordingShortcut,
                appState.isRecordingQuickPasteShortcut,
                appState.isRecordingLocalAltPasteShortcut,
                appState.isRecordingGlobalAltPasteShortcut,
                appState.isRecordingItemShortcut,
                appState.itemShortcutsChangedID
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
        let isSettingsWindow = SettingsWindowController.shared.isVisible && event.window == SettingsWindowController.shared.window
        guard event.window == panel || isSettingsWindow else {
            return event
        }

        if shouldSuppressKeyUp(event) {
            return nil
        }

        guard event.type == .keyDown else {
            return event
        }

        // When recording shortcuts from the settings window, only handle recording events
        if isSettingsWindow {
            let anyRecording = appState.isRecordingShortcut || appState.isRecordingQuickPasteShortcut || appState.isRecordingLocalAltPasteShortcut || appState.isRecordingGlobalAltPasteShortcut
            guard anyRecording else { return event }
        }

        return handleKeyDownEvent(event)
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        guard isPanelVisible else {
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if appState.isRecordingItemShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingItemShortcut = false
                appState.itemShortcutError = nil
            default:
                appState.updateItemShortcut(from: event)
            }
            return suppressKeyUp(for: event)
        }

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

        if appState.isRecordingLocalAltPasteShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingLocalAltPasteShortcut = false
            default:
                appState.updateAltPasteShortcut(from: event)
            }
            return suppressKeyUp(for: event)
        }

        if appState.isRecordingGlobalAltPasteShortcut {
            switch event.keyCode {
            case 53:
                appState.isRecordingGlobalAltPasteShortcut = false
            default:
                appState.updateGlobalAltPasteShortcut(from: event)
            }
            return suppressKeyUp(for: event)
        }

        let localAlt = appState.settings.localAltPasteShortcut
        if UInt32(event.keyCode) == localAlt.keyCode && modifiers == localAlt.modifiers {
            appState.requestAltPaste()
            return suppressKeyUp(for: event)
        }

        #if DEBUG
        if event.keyCode == 32 && modifiers == .control { // Ctrl+U — cycle update phases
            cycleDebugUpdatePhase()
            return suppressKeyUp(for: event)
        }
        #endif

        if !modifiers.isDisjoint(with: [.command, .option, .control]) {
            return event
        }

        if appState.showingFavoriteTabPicker {
            return suppressKeyUp(for: event)
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
            guard modifiers.isEmpty else { return event }
            appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
            return suppressKeyUp(for: event)
        case 51, 117: // Backspace, Forward Delete
            guard appState.searchQuery.isEmpty else { return event }
            appState.deleteSelectedItem()
            return suppressKeyUp(for: event)
        case 116: // Page Up
            appState.moveSelectionByPage(direction: -1)
            return suppressKeyUp(for: event)
        case 121: // Page Down
            appState.moveSelectionByPage(direction: 1)
            return suppressKeyUp(for: event)
        case 115: // Home
            appState.moveToFirst()
            return suppressKeyUp(for: event)
        case 119: // End
            appState.moveToLast()
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
    private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusItemMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Clipiary", action: #selector(togglePopover), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        if updaterManager.isConfigured {
            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Clipiary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func checkForUpdates() {
        updaterManager.checkForUpdates()
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
            let panelFrame = panel.frame
            if ThemeBuilderWindowController.shared.isVisible {
                DispatchQueue.main.async {
                    ThemeBuilderWindowController.shared.orderFront(adjacentTo: panelFrame)
                }
            }
            if SettingsWindowController.shared.isVisible {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.orderFront()
                }
            }
        }
    }

    private func panelDidClose() {
        statusItem.button?.isHighlighted = false
        appState.isRecordingShortcut = false
        appState.isRecordingQuickPasteShortcut = false
        appState.isRecordingItemShortcut = false
        appState.itemShortcutError = nil
        appState.showingFavoriteTabPicker = false
        appState.isPreviewVisible = false
        appState.searchQuery = ""
        suppressedKeyUps.removeAll()
        let targetApp = previousApp
        previousApp = nil
        // Only restore the previous app if the user hasn't already switched away
        // (e.g. via Cmd+Tab). If the frontmost app is already something else, respect that.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
            targetApp?.activate()
        }
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

    #if DEBUG
    private func cycleDebugUpdatePhase() {
        UpdaterManager.shared.cycleDebugPhase()
    }
    #endif
}
