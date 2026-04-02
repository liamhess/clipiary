import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    struct PopoverTab: Identifiable, Equatable, Hashable {
        enum Kind: Equatable, Hashable {
            case history
            case favorites(tabName: String)
        }

        let kind: Kind

        var id: String {
            switch kind {
            case .history: return "__history__"
            case .favorites(let name): return "fav:\(name)"
            }
        }

        var displayName: String {
            switch kind {
            case .history: return "History"
            case .favorites(let name): return name
            }
        }

        static let history = PopoverTab(kind: .history)

        static func favorites(_ name: String) -> PopoverTab {
            PopoverTab(kind: .favorites(tabName: name))
        }
    }

    static let shared = AppState()

    let settings: AppSettings
    let history: HistoryStore
    let permissionManager: AccessibilityPermissionManager
    let configManager: ConfigManager
    let themeManager: ThemeManager
    var selectedTab: PopoverTab = .history
    var searchQuery = ""
    private var selectedItemIDByTab: [String: HistoryItem.ID] = [:]
    var isRecordingShortcut = false
    var isRecordingQuickPasteShortcut = false
    var isPreviewVisible = false
    var showingFavoriteTabPicker = false
    var favoriteTabPickerIndex = 0
    var isRecordingItemShortcut = false
    var isEditingSnippetDescription = false
    var isEditingItemText = false
    var itemShortcutError: String?
    private(set) var itemShortcutsChangedID = 0
    private(set) var searchFocusRequestID = 0
    private(set) var popoverOpenRequestID = 0
    private(set) var pasteSelectedRequestID = 0
    private(set) var quickPasteRequestID = 0

    @ObservationIgnored private let captureCoordinator: CaptureCoordinator
    @ObservationIgnored private let clipboardMonitor: ClipboardMonitor
    @ObservationIgnored private let copyOnSelectEngine: CopyOnSelectEngine

    private init() {
        let settings = AppSettings()
        let history = HistoryStore()
        let permissionManager = AccessibilityPermissionManager()
        let configManager = ConfigManager()
        let themeManager = ThemeManager()
        self.settings = settings
        self.history = history
        self.permissionManager = permissionManager
        self.configManager = configManager
        self.themeManager = themeManager
        let captureCoordinator = CaptureCoordinator(history: history, settings: settings)
        self.captureCoordinator = captureCoordinator
        self.clipboardMonitor = ClipboardMonitor(settings: settings, captureCoordinator: captureCoordinator)
        self.copyOnSelectEngine = CopyOnSelectEngine(
            settings: settings,
            permissionManager: permissionManager,
            captureCoordinator: captureCoordinator
        )
    }

    init(
        settings: AppSettings,
        history: HistoryStore,
        configManager: ConfigManager,
        permissionManager: AccessibilityPermissionManager,
        themeManager: ThemeManager = ThemeManager()
    ) {
        self.settings = settings
        self.history = history
        self.configManager = configManager
        self.permissionManager = permissionManager
        self.themeManager = themeManager
        let captureCoordinator = CaptureCoordinator(history: history, settings: settings)
        self.captureCoordinator = captureCoordinator
        self.clipboardMonitor = ClipboardMonitor(settings: settings, captureCoordinator: captureCoordinator)
        self.copyOnSelectEngine = CopyOnSelectEngine(
            settings: settings,
            permissionManager: permissionManager,
            captureCoordinator: captureCoordinator
        )
    }

    func start() {
        configManager.load()
        history.load()
        themeManager.ensureDefaultTheme()
        themeManager.load()
        themeManager.selectTheme(id: settings.selectedThemeID)
        themeManager.startWatching()
        restoreMissingTabs()
        seedConfigEntries()
        history.enforceLimit(settings.historyLimit)
        permissionManager.refreshTrust()
        clipboardMonitor.start()
        copyOnSelectEngine.start()
        captureCoordinator.startPasteMonitor()
        ensureSelection()
        synchronizeHistoryLimit()
        synchronizeThemeSelection()
    }

    func refreshCopyOnSelectPermissions() {
        permissionManager.openPrivacySettings()
    }

    func restore(_ item: HistoryItem) {
        captureCoordinator.restore(item)
    }

    func didOpenPopover() {
        selectedTab = .history
        selectedItemIDByTab[PopoverTab.history.id] = nil
        isPreviewVisible = false
        showingFavoriteTabPicker = false
        ensureSelection()
        popoverOpenRequestID &+= 1
        requestSearchFocus()
    }

    var allTabs: [PopoverTab] {
        var tabs: [PopoverTab] = [.history]
        for tabConfig in configManager.favoriteTabs {
            tabs.append(.favorites(tabConfig.name))
        }
        return tabs
    }

    func addFavoriteTab(name: String) {
        configManager.addTab(name: name)
    }

    func deleteFavoriteTab(name: String) {
        if case .favorites(let selected) = selectedTab.kind, selected == name {
            selectedTab = .history
        }
        configManager.deleteTab(name: name)
        history.removeTabFromAllItems(tabName: name)
    }

    func renameFavoriteTab(oldName: String, newName: String) {
        if case .favorites(let selected) = selectedTab.kind, selected == oldName {
            selectedTab = .favorites(newName)
        }
        configManager.renameTab(oldName: oldName, newName: newName)
        history.renameTabInAllItems(oldName: oldName, newName: newName)
    }

    func moveFavoriteTab(from source: Int, to destination: Int) {
        configManager.moveTab(from: source, to: destination)
    }

    var historyItems: [HistoryItem] {
        filteredItems(for: .history)
    }

    func favoriteItems(for tabName: String) -> [HistoryItem] {
        let tabItems = filteredItems().filter { $0.favoriteTabs.contains(tabName) }
        return history.customOrderedItems(tabItems)
    }

    var activeItems: [HistoryItem] {
        filteredItems(for: selectedTab)
    }

    var selectedHistoryItemID: HistoryItem.ID? {
        get { selectedItemIDByTab[selectedTab.id] }
        set { selectedItemIDByTab[selectedTab.id] = newValue }
    }

    func filteredItems(for tab: PopoverTab) -> [HistoryItem] {
        let baseItems = filteredItems()
        switch tab.kind {
        case .history:
            return baseItems.filter { !$0.isSeparator }.sorted { $0.createdAt > $1.createdAt }
        case .favorites(let tabName):
            return history.customOrderedItems(baseItems.filter { $0.favoriteTabs.contains(tabName) })
        }
    }

    func filteredItems() -> [HistoryItem] {
        let terms = searchQuery.split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else {
            return history.items
        }

        return history.items.filter { item in
            terms.allSatisfy { term in
                item.text.localizedCaseInsensitiveContains(term) ||
                item.appName.localizedCaseInsensitiveContains(term) ||
                (item.bundleID?.localizedCaseInsensitiveContains(term) ?? false) ||
                (item.snippetDescription?.localizedCaseInsensitiveContains(term) ?? false)
            }
        }
    }

    func setSelectedTab(_ tab: PopoverTab) {
        selectedTab = tab
        ensureSelection()
        requestSearchFocus()
    }

    func moveTab(direction: Int) {
        let tabs = allTabs
        guard let index = tabs.firstIndex(of: selectedTab) else {
            return
        }

        let nextIndex = min(max(index + direction, 0), tabs.count - 1)
        setSelectedTab(tabs[nextIndex])
    }

    func togglePreview() {
        isPreviewVisible.toggle()
        if !isPreviewVisible {
            requestSearchFocus()
        }
    }

    func moveSelection(direction: Int) {
        let items = activeItems
        guard !items.isEmpty else {
            selectedHistoryItemID = nil
            return
        }

        guard let currentSelectionID = selectedHistoryItemID,
              let currentIndex = items.firstIndex(where: { $0.id == currentSelectionID }) else {
            selectedHistoryItemID = direction >= 0 ? items.first?.id : items.last?.id
            return
        }

        let nextIndex = min(max(currentIndex + direction, 0), items.count - 1)
        // Skip over separators
        var resolved = nextIndex
        let step = direction > 0 ? 1 : -1
        while resolved > 0 && resolved < items.count - 1 && items[resolved].isSeparator {
            resolved += step
        }
        // If we ended up on a separator at the boundary, keep the original position
        if items[resolved].isSeparator {
            resolved = currentIndex
        }
        selectedHistoryItemID = items[resolved].id
    }

    func moveSelectionByPage(direction: Int) {
        let pageSize = 10
        moveSelection(direction: direction * pageSize)
    }

    func moveToFirst() {
        let items = activeItems
        guard !items.isEmpty else { return }
        selectedHistoryItemID = items.first?.id
    }

    func moveToLast() {
        let items = activeItems
        guard !items.isEmpty else { return }
        selectedHistoryItemID = items.last?.id
    }

    func ensureSelection() {
        let items = activeItems
        guard !items.isEmpty else {
            selectedHistoryItemID = nil
            return
        }

        if let selectedHistoryItemID,
           items.contains(where: { $0.id == selectedHistoryItemID }) {
            return
        }

        selectedHistoryItemID = items.first(where: { !$0.isSeparator })?.id
    }

    func restoreSelectedItem() {
        guard let item = selectedItem, !item.isSeparator else {
            return
        }
        history.markAsPasted(item)
        restore(item)
        if settings.moveToTopOnPaste && !(settings.moveToTopSkipFavorites && item.isFavorite) {
            history.moveToTop(item)
        }
    }

    func toggleFavoriteSelectedItem() {
        guard selectedItem != nil else {
            return
        }

        let favTabs = configManager.favoriteTabs
        if favTabs.count == 1 {
            toggleFavoriteTab(selectedItem!, tabName: favTabs[0].name)
            ensureSelection()
        } else {
            favoriteTabPickerIndex = 0
            showingFavoriteTabPicker = true
        }
    }

    func addSelectedItemToFavoriteTab(_ tabName: String) {
        guard let item = selectedItem else {
            return
        }
        toggleFavoriteTab(item, tabName: tabName)
        showingFavoriteTabPicker = false
        ensureSelection()
    }

    func movePickerSelection(direction: Int) {
        let count = configManager.favoriteTabs.count
        guard count > 0 else { return }
        favoriteTabPickerIndex = min(max(favoriteTabPickerIndex + direction, 0), count - 1)
    }

    func confirmPickerSelection() {
        let tabs = configManager.favoriteTabs
        guard let item = selectedItem,
              favoriteTabPickerIndex >= 0, favoriteTabPickerIndex < tabs.count else { return }
        toggleFavoriteTab(item, tabName: tabs[favoriteTabPickerIndex].name)
        ensureSelection()
    }

    func toggleFavoriteTab(_ item: HistoryItem, tabName: String) {
        if item.favoriteTabs.contains(tabName), configManager.isSeededEntry(item.text, inTab: tabName) {
            return
        }
        history.toggleFavoriteTab(item, tabName: tabName)
    }

    func insertSeparator(after item: HistoryItem, inTab tabName: String) {
        let sep = HistoryItem(
            text: "",
            source: .restored,
            appName: "",
            bundleID: nil,
            favoriteTabs: [tabName],
            isSeparator: true
        )
        history.insertSeparator(sep, after: item, inTab: tabName)
    }

    func removeSeparator(_ item: HistoryItem) {
        guard item.isSeparator else { return }
        history.delete(item)
    }

    func togglePickerMonospace() {
        guard let item = selectedItem else { return }
        history.toggleMonospace(item)
    }

    func setSnippetDescription(_ description: String?) {
        guard let item = selectedItem else { return }
        history.setSnippetDescription(description, for: item)
    }

    func setItemText(_ text: String) {
        guard let item = selectedItem else { return }
        history.setText(text, for: item)
    }

    func startRecordingItemShortcut() {
        isRecordingItemShortcut = true
        itemShortcutError = nil
    }

    func removeItemShortcut() {
        guard let item = selectedItem, item.shortcutKeyCode != nil else { return }
        history.removeShortcut(for: item)
        itemShortcutsChangedID &+= 1
    }

    func updateItemShortcut(from event: NSEvent) {
        guard let shortcut = GlobalShortcut(event: event) else { return }
        guard let item = selectedItem else {
            isRecordingItemShortcut = false
            return
        }

        if let collision = shortcutCollision(shortcut, excludingItemID: item.id) {
            itemShortcutError = collision
            return
        }

        history.setShortcut(shortcut, for: item)
        isRecordingItemShortcut = false
        itemShortcutError = nil
        itemShortcutsChangedID &+= 1
    }

    func requestItemPaste(itemID: UUID) {
        guard let item = history.items.first(where: { $0.id == itemID }), !item.isSeparator else { return }
        history.markAsPasted(item)
        restore(item)
        if settings.moveToTopOnPaste && !(settings.moveToTopSkipFavorites && item.isFavorite) {
            history.moveToTop(item)
        }
        quickPasteRequestID &+= 1
    }

    func shortcutCollision(_ shortcut: GlobalShortcut, excludingItemID: UUID? = nil) -> String? {
        if shortcut == settings.globalShortcut {
            return "Already used to open Clipiary"
        }
        if shortcut == settings.quickPasteShortcut {
            return "Already used for quick paste"
        }
        for item in history.items where item.id != excludingItemID {
            if let existing = item.globalShortcut, existing == shortcut {
                let label = String(item.displayText.prefix(20))
                return "Already assigned to \"\(label)\""
            }
        }
        return nil
    }

    func reorderItem(_ itemID: HistoryItem.ID, toIndex: Int) {
        let currentItems = activeItems
        // Ensure all items in the current view have explicit sortIndex values
        let needsAssignment = Set(currentItems.filter { $0.sortIndex == nil }.map(\.id))
        if !needsAssignment.isEmpty {
            history.assignSortIndices(to: Set(currentItems.map(\.id)))
        }
        // Re-fetch after assignment
        let orderedItems = filteredItems(for: selectedTab)
        history.moveItem(itemID, toIndex: toIndex, inOrderedItems: orderedItems)
    }

    func deleteSelectedItem() {
        guard let item = selectedItem else {
            return
        }

        let hadShortcut = item.shortcutKeyCode != nil

        // Determine the neighbor to select after deletion so the scroll position stays stable.
        let items = activeItems
        let neighborID: HistoryItem.ID? = {
            guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return nil }
            if idx + 1 < items.count { return items[idx + 1].id }
            if idx - 1 >= 0 { return items[idx - 1].id }
            return nil
        }()

        history.delete(item)
        selectedHistoryItemID = neighborID
        if hadShortcut { itemShortcutsChangedID &+= 1 }
    }

    var selectedItem: HistoryItem? {
        guard let selectedHistoryItemID else {
            return nil
        }

        return activeItems.first(where: { $0.id == selectedHistoryItemID })
    }

    func clearSelection(for tab: PopoverTab) {
        selectedItemIDByTab[tab.id] = nil
    }

    func updateGlobalShortcut(from event: NSEvent) {
        guard let shortcut = GlobalShortcut(event: event) else {
            return
        }

        settings.updateGlobalShortcut(shortcut)
        isRecordingShortcut = false
    }

    func updateQuickPasteShortcut(from event: NSEvent) {
        guard let shortcut = GlobalShortcut(event: event) else {
            return
        }

        settings.updateQuickPasteShortcut(shortcut)
        isRecordingQuickPasteShortcut = false
    }

    func requestSearchFocus() {
        searchFocusRequestID &+= 1
    }

    func requestPasteSelected() {
        restoreSelectedItem()
        searchQuery = ""
        isPreviewVisible = false
        pasteSelectedRequestID &+= 1
    }

    func requestQuickPaste() {
        guard history.items.count >= 2 else { return }
        let item = history.items[1]
        history.markAsPasted(item)
        restore(item)
        if settings.moveToTopOnPaste && !(settings.moveToTopSkipFavorites && item.isFavorite) {
            history.moveToTop(item)
        }
        quickPasteRequestID &+= 1
    }

    private func restoreMissingTabs() {
        let knownTabs = Set(configManager.favoriteTabs.map(\.name))
        var missingTabs: [String] = []
        for item in history.items {
            for tabName in item.favoriteTabs where !knownTabs.contains(tabName) && !missingTabs.contains(tabName) {
                missingTabs.append(tabName)
            }
        }
        for tabName in missingTabs {
            configManager.addTab(name: tabName)
        }
    }

    private func seedConfigEntries() {
        for tab in configManager.tabsWithEntries {
            history.seedEntries(for: tab)
        }
    }

    private func synchronizeHistoryLimit() {
        _ = withObservationTracking {
            settings.historyLimit
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.history.enforceLimit(self.settings.historyLimit)
                self.ensureSelection()
                self.synchronizeHistoryLimit()
            }
        }
    }

    private func synchronizeThemeSelection() {
        _ = withObservationTracking {
            settings.selectedThemeID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.themeManager.selectTheme(id: self.settings.selectedThemeID)
                self.synchronizeThemeSelection()
            }
        }
    }
}
