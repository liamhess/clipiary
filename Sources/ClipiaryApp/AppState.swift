import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum PopoverTab: String, CaseIterable, Identifiable {
        case history = "History"
        case favorites = "Favorites"

        var id: Self { self }
    }

    static let shared = AppState()

    let settings = AppSettings()
    let history = HistoryStore()
    let permissionManager = AccessibilityPermissionManager()
    var selectedTab: PopoverTab = .history
    var searchQuery = ""
    private var selectedHistoryTabItemID: HistoryItem.ID?
    private var selectedFavoritesTabItemID: HistoryItem.ID?
    var isRecordingShortcut = false
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
        history.load()
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
        selectedHistoryTabItemID = nil
        ensureSelection()
        popoverOpenRequestID &+= 1
        requestSearchFocus()
    }

    var historyItems: [HistoryItem] {
        filteredItems(for: .history)
    }

    var favoriteItems: [HistoryItem] {
        filteredItems(for: .favorites)
    }

    var activeItems: [HistoryItem] {
        selectedTab == .history ? historyItems : favoriteItems
    }

    var selectedHistoryItemID: HistoryItem.ID? {
        get {
            switch selectedTab {
            case .history:
                selectedHistoryTabItemID
            case .favorites:
                selectedFavoritesTabItemID
            }
        }
        set {
            switch selectedTab {
            case .history:
                selectedHistoryTabItemID = newValue
            case .favorites:
                selectedFavoritesTabItemID = newValue
            }
        }
    }

    func filteredItems(for tab: PopoverTab) -> [HistoryItem] {
        let baseItems = filteredItems()
        switch tab {
        case .history:
            return baseItems
        case .favorites:
            return baseItems.filter(\.isFavorite)
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
        let tabs = PopoverTab.allCases
        guard let index = tabs.firstIndex(of: selectedTab) else {
            return
        }

        let nextIndex = min(max(index + direction, 0), tabs.count - 1)
        setSelectedTab(tabs[nextIndex])
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
        guard let item = selectedItem else {
            return
        }
        history.toggleFavorite(item)
        ensureSelection()
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
        switch tab {
        case .history:
            selectedHistoryTabItemID = nil
        case .favorites:
            selectedFavoritesTabItemID = nil
        }
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
        pasteSelectedRequestID &+= 1
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
