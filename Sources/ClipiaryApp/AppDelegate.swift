import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    private var statusSyncTimer: Timer?
    private let rootMenu = NSMenu()
    private let historyMenu = NSMenu(title: "History")
    private var historyQuery = ""
    private lazy var historySearchField: NSSearchField = {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Search history"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        return field
    }()
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        item.button?.image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "Clipiary")
        item.button?.imagePosition = .imageLeft
        item.menu = rootMenu
        return item
    }()

    private let appState = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        appState.start()
        configureMenus()
        updateStatusItem()
        statusSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.rebuildMenus()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isAutoSelectEnabled
        button.appearsDisabled = isPaused

        if appState.settings.showRecentItemInStatusBar, let text = appState.history.items.first?.displayText {
            button.title = " " + text.prefix(18)
        } else {
            button.title = ""
        }
    }

    private func configureMenus() {
        rootMenu.delegate = self
        historyMenu.delegate = self
        rebuildMenus()
    }

    private func rebuildMenus() {
        rebuildRootMenu()
        rebuildHistoryMenu()
    }

    private func rebuildRootMenu() {
        rootMenu.removeAllItems()

        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        rootMenu.addItem(historyItem)

        rootMenu.addItem(.separator())
        rootMenu.addItem(toggleItem(
            title: "Clipboard Monitoring",
            isOn: appState.settings.isClipboardMonitoringEnabled,
            action: #selector(toggleClipboardMonitoring)
        ))
        rootMenu.addItem(toggleItem(
            title: "Autoselect",
            isOn: appState.settings.isAutoSelectEnabled,
            action: #selector(toggleAutoSelect)
        ))

        if !appState.permissionManager.isTrusted {
            rootMenu.addItem(.separator())
            rootMenu.addItem(menuItem(title: "Grant Accessibility Access", action: #selector(grantAccessibilityAccess)))
        }

        rootMenu.addItem(.separator())
        rootMenu.addItem(menuItem(title: "Clear History", action: #selector(clearHistory)))
        rootMenu.addItem(menuItem(title: "Quit Clipiary", action: #selector(quit)))
    }

    private func rebuildHistoryMenu() {
        historyMenu.removeAllItems()
        historyMenu.autoenablesItems = false

        let searchItem = NSMenuItem()
        searchItem.isEnabled = false
        searchItem.view = historySearchContainer()
        historyMenu.addItem(searchItem)
        historyMenu.addItem(.separator())

        let items = filteredHistoryItems()
        if items.isEmpty {
            let emptyItem = NSMenuItem(title: historyQuery.isEmpty ? "No clipboard history yet" : "No matching history items", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
            return
        }

        for item in items.prefix(30) {
            historyMenu.addItem(historyMenuItem(for: item))
        }

        historyMenu.addItem(.separator())
        historyMenu.addItem(menuItem(title: "Clear Search", action: #selector(clearHistorySearch)))
    }

    private func filteredHistoryItems() -> [HistoryItem] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appState.history.items
        }

        return appState.history.items.filter { item in
            item.text.localizedCaseInsensitiveContains(query) ||
            item.appName.localizedCaseInsensitiveContains(query) ||
            (item.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func historyMenuTitle(for item: HistoryItem) -> String {
        let pinPrefix = item.isPinned ? "[P] " : ""
        let sourcePrefix = item.source == .autoSelect ? "[A] " : ""
        let title = item.displayText.isEmpty ? "Untitled" : item.displayText
        let compact = title.count > 60 ? String(title.prefix(57)) + "..." : title
        return "\(pinPrefix)\(sourcePrefix)\(compact)"
    }

    private func historyMenuItem(for item: HistoryItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: historyMenuTitle(for: item), action: #selector(restoreHistoryItem(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item.id.uuidString

        let submenu = NSMenu(title: historyMenuTitle(for: item))
        submenu.autoenablesItems = false

        let restoreItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(restoreHistoryItem(_:)), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.representedObject = item.id.uuidString
        submenu.addItem(restoreItem)

        let pinTitle = item.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinnedHistoryItem(_:)), keyEquivalent: "")
        pinItem.target = self
        pinItem.representedObject = item.id.uuidString
        submenu.addItem(pinItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteHistoryItem(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item.id.uuidString
        submenu.addItem(deleteItem)

        submenu.addItem(.separator())
        let detailItem = NSMenuItem(title: detailTitle(for: item), action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        submenu.addItem(detailItem)

        menuItem.submenu = submenu
        return menuItem
    }

    private func detailTitle(for item: HistoryItem) -> String {
        let source = item.source == .autoSelect ? "Autoselect" : "Clipboard"
        return "\(item.appName) • \(source)"
    }

    private func historySearchContainer() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 276, height: 30))
        historySearchField.stringValue = historyQuery
        historySearchField.frame = NSRect(x: 8, y: 3, width: 260, height: 24)
        container.addSubview(historySearchField)
        return container
    }

    private func toggleItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = menuItem(title: title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == rootMenu {
            rebuildRootMenu()
        } else if menu == historyMenu {
            rebuildHistoryMenu()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field == historySearchField else {
            return
        }

        historyQuery = field.stringValue
        rebuildHistoryMenu()
    }

    @objc
    private func toggleClipboardMonitoring() {
        appState.settings.isClipboardMonitoringEnabled.toggle()
        updateStatusItem()
        rebuildMenus()
    }

    @objc
    private func toggleAutoSelect() {
        appState.settings.isAutoSelectEnabled.toggle()
        updateStatusItem()
        rebuildMenus()
    }

    @objc
    private func grantAccessibilityAccess() {
        appState.refreshAutoSelectPermissions()
        rebuildMenus()
    }

    @objc
    private func clearHistory() {
        appState.history.clearUnpinned()
        rebuildMenus()
    }

    @objc
    private func clearHistorySearch() {
        historyQuery = ""
        historySearchField.stringValue = ""
        rebuildHistoryMenu()
    }

    @objc
    private func restoreHistoryItem(_ sender: NSMenuItem) {
        guard let item = historyItem(from: sender) else {
            return
        }

        appState.restore(item)
        rebuildMenus()
    }

    @objc
    private func togglePinnedHistoryItem(_ sender: NSMenuItem) {
        guard let item = historyItem(from: sender) else {
            return
        }

        appState.history.togglePin(item)
        rebuildMenus()
    }

    @objc
    private func deleteHistoryItem(_ sender: NSMenuItem) {
        guard let item = historyItem(from: sender) else {
            return
        }

        appState.history.delete(item)
        rebuildMenus()
    }

    private func historyItem(from sender: NSMenuItem) -> HistoryItem? {
        guard let identifier = sender.representedObject as? String,
              let uuid = UUID(uuidString: identifier) else {
            return nil
        }

        return appState.history.items.first(where: { $0.id == uuid })
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
