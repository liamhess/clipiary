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

    let settings = AppSettings()
    let history = HistoryStore()
    let permissionManager = AccessibilityPermissionManager()
    let configManager = ConfigManager()
    var selectedTab: PopoverTab = .history
    var searchQuery = ""
    private var selectedItemIDByTab: [String: HistoryItem.ID] = [:]
    var isRecordingShortcut = false
    var isPreviewVisible = false
    var showingFavoriteTabPicker = false
    var favoriteTabPickerIndex = 0
    private(set) var searchFocusRequestID = 0
    private(set) var popoverOpenRequestID = 0
    private(set) var pasteSelectedRequestID = 0

    @ObservationIgnored private let captureCoordinator: CaptureCoordinator
    @ObservationIgnored private let clipboardMonitor: ClipboardMonitor
    @ObservationIgnored private let copyOnSelectEngine: CopyOnSelectEngine

    private init() {
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
        seedConfigEntries()
        history.enforceLimit(settings.historyLimit)
        permissionManager.refreshTrust()
        clipboardMonitor.start()
        copyOnSelectEngine.start()
        ensureSelection()
        synchronizeHistoryLimit()
    }

    func refreshCopyOnSelectPermissions() {
        permissionManager.requestAccessPrompt()
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

    var historyItems: [HistoryItem] {
        filteredItems(for: .history)
    }

    func favoriteItems(for tabName: String) -> [HistoryItem] {
        filteredItems().filter { $0.favoriteTabs.contains(tabName) }
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
            return baseItems
        case .favorites(let tabName):
            return baseItems.filter { $0.favoriteTabs.contains(tabName) }
        }
    }

    func filteredItems() -> [HistoryItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return history.items
        }

        return history.items.filter { item in
            item.text.localizedCaseInsensitiveContains(query) ||
            item.appName.localizedCaseInsensitiveContains(query) ||
            (item.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
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
        isPreviewVisible = false
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
        selectedHistoryItemID = items[nextIndex].id
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

        selectedHistoryItemID = items.first?.id
    }

    func restoreSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        restore(item)
        if settings.moveToTopOnPaste {
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

    func deleteSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        history.delete(item)
        ensureSelection()
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

    func requestSearchFocus() {
        searchFocusRequestID &+= 1
    }

    func requestPasteSelected() {
        restoreSelectedItem()
        searchQuery = ""
        isPreviewVisible = false
        pasteSelectedRequestID &+= 1
    }

    private func seedConfigEntries() {
        let unseeded = configManager.unseededTabs()
        guard !unseeded.isEmpty else { return }
        for tab in unseeded {
            history.seedEntries(for: tab)
        }
        configManager.markSeeded(unseeded.map(\.name))
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
}
