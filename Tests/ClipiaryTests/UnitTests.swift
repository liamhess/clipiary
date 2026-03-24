import Foundation
import Testing
@testable import ClipiaryLib

// MARK: - Test Helpers

@MainActor
func makeTestAppState() -> AppState {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let history = HistoryStore(storageDirectory: tempDir)
    let configManager = ConfigManager(storageDirectory: tempDir)
    let permissionManager = AccessibilityPermissionManager()
    return AppState(
        settings: settings,
        history: history,
        configManager: configManager,
        permissionManager: permissionManager
    )
}

func makeItem(
    text: String = "test",
    source: CaptureSource = .clipboard,
    appName: String = "App",
    bundleID: String? = nil,
    createdAt: Date = .now,
    favoriteTabs: Set<String> = [],
    isMonospace: Bool = false,
    imageFileName: String? = nil,
    pasteCount: Int = 0
) -> HistoryItem {
    HistoryItem(
        text: text,
        source: source,
        appName: appName,
        bundleID: bundleID,
        createdAt: createdAt,
        favoriteTabs: favoriteTabs,
        isMonospace: isMonospace,
        imageFileName: imageFileName,
        pasteCount: pasteCount
    )
}

// MARK: - HistoryItem Model Tests

@Suite struct HistoryItemTests {
    @Test func displayTextCollapsesNewlines() {
        let item = makeItem(text: "line1\nline2\nline3")
        #expect(item.displayText == "line1 line2 line3")
    }

    @Test func displayTextTrimsWhitespace() {
        let item = makeItem(text: "  hello  \n")
        #expect(item.displayText == "hello")
    }

    @Test func isImageWhenImageFileNamePresent() {
        let item = makeItem(imageFileName: "test.png")
        #expect(item.isImage == true)
    }

    @Test func isNotImageWhenNoFileName() {
        let item = makeItem()
        #expect(item.isImage == false)
    }

    @Test func isFavoriteWhenTabsNotEmpty() {
        let item = makeItem(favoriteTabs: ["Favorites"])
        #expect(item.isFavorite == true)
    }

    @Test func isNotFavoriteWhenTabsEmpty() {
        let item = makeItem()
        #expect(item.isFavorite == false)
    }

    @Test func codableRoundTrip() throws {
        let original = makeItem(
            text: "encoded text",
            source: .copyOnSelect,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            favoriteTabs: ["Tab1", "Tab2"],
            isMonospace: true,
            pasteCount: 5
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HistoryItem.self, from: data)
        #expect(decoded.text == original.text)
        #expect(decoded.source == original.source)
        #expect(decoded.favoriteTabs == original.favoriteTabs)
        #expect(decoded.isMonospace == original.isMonospace)
        #expect(decoded.pasteCount == original.pasteCount)
        #expect(decoded.bundleID == original.bundleID)
    }

    @Test func legacyIsFavoriteDecoding() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "text": "legacy",
            "source": "clipboard",
            "appName": "App",
            "createdAt": "2024-01-01T00:00:00Z",
            "isFavorite": true,
            "monospace": false,
            "wasPasted": false,
            "pasteCount": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(HistoryItem.self, from: json.data(using: .utf8)!)
        #expect(item.favoriteTabs == ["Favorites"])
    }

    @Test func legacyIsFavoriteFalseDecoding() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "text": "legacy",
            "source": "clipboard",
            "appName": "App",
            "createdAt": "2024-01-01T00:00:00Z",
            "isFavorite": false,
            "monospace": false,
            "wasPasted": false,
            "pasteCount": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(HistoryItem.self, from: json.data(using: .utf8)!)
        #expect(item.favoriteTabs.isEmpty)
    }
}

// MARK: - AppSettings Tests

@MainActor
@Suite struct AppSettingsTests {
    @Test func defaultValues() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.isClipboardMonitoringEnabled == true)
        #expect(settings.historyLimit == 1000)
        #expect(settings.moveToTopOnPaste == true)
        #expect(settings.isCopyOnSelectEnabled == false)
    }

    @Test func persistsChanges() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = 500

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.historyLimit == 500)
    }

    @Test func toggleIgnoredBundleID() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.toggleIgnored(bundleID: "com.example.app")
        #expect(settings.ignoredBundleIDs.contains("com.example.app"))
        #expect(settings.ignores(bundleID: "com.example.app") == true)

        settings.toggleIgnored(bundleID: "com.example.app")
        #expect(!settings.ignoredBundleIDs.contains("com.example.app"))
        #expect(settings.ignores(bundleID: "com.example.app") == false)
    }

    @Test func ignoresNilBundleID() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.ignores(bundleID: nil) == false)
    }
}

// MARK: - HistoryStore Tests

@MainActor
@Suite struct HistoryStoreTests {
    private func makeTempStore() -> HistoryStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return HistoryStore(storageDirectory: dir)
    }

    @Test func addAndRetrieve() {
        let store = makeTempStore()
        let item = makeItem(text: "hello")
        store.add(item, limit: 100)
        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hello")
    }

    @Test func deduplicatesSameTextAndBundle() {
        let store = makeTempStore()
        let item1 = makeItem(text: "dup", bundleID: "com.test")
        let item2 = makeItem(text: "dup", bundleID: "com.test")
        store.add(item1, limit: 100)
        store.add(item2, limit: 100)
        #expect(store.items.count == 1)
    }

    @Test func doesNotDeduplicateDifferentBundles() {
        let store = makeTempStore()
        let item1 = makeItem(text: "same", bundleID: "com.a")
        let item2 = makeItem(text: "same", bundleID: "com.b")
        store.add(item1, limit: 100)
        store.add(item2, limit: 100)
        #expect(store.items.count == 2)
    }

    @Test func enforcesLimit() {
        let store = makeTempStore()
        for i in 0..<10 {
            store.add(makeItem(text: "item \(i)"), limit: 5)
        }
        #expect(store.items.count == 5)
    }

    @Test func persistAndLoad() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store1 = HistoryStore(storageDirectory: dir)
        store1.add(makeItem(text: "persisted"), limit: 100)

        let store2 = HistoryStore(storageDirectory: dir)
        store2.load()
        #expect(store2.items.count == 1)
        #expect(store2.items[0].text == "persisted")
    }
}

// MARK: - AppState Filtering Tests

@MainActor
@Suite struct AppStateFilteringTests {
    @Test func filteredItemsReturnsAllWhenSearchEmpty() {
        let appState = makeTestAppState()
        appState.history.add(makeItem(text: "hello"), limit: 100)
        appState.searchQuery = ""
        #expect(appState.filteredItems().count == 1)
    }

    @Test func filteredItemsMatchesText() {
        let appState = makeTestAppState()
        appState.history.add(makeItem(text: "hello world"), limit: 100)
        appState.history.add(makeItem(text: "goodbye"), limit: 100)
        appState.searchQuery = "hello"
        #expect(appState.filteredItems().count == 1)
        #expect(appState.filteredItems()[0].text == "hello world")
    }

    @Test func filteredItemsMatchesAppName() {
        let appState = makeTestAppState()
        appState.history.add(makeItem(text: "some text", appName: "Safari"), limit: 100)
        appState.searchQuery = "Safari"
        #expect(appState.filteredItems().count == 1)
    }

    @Test func filteredItemsMultiTermSearch() {
        let appState = makeTestAppState()
        appState.history.add(makeItem(text: "hello world", appName: "Safari"), limit: 100)
        appState.history.add(makeItem(text: "hello there", appName: "Chrome"), limit: 100)
        appState.searchQuery = "hello Safari"
        let results = appState.filteredItems()
        #expect(results.count == 1)
        #expect(results[0].appName == "Safari")
    }

    @Test func historyItemsSortedByRecency() {
        let appState = makeTestAppState()
        let older = makeItem(text: "older", createdAt: Date(timeIntervalSince1970: 1000))
        let newer = makeItem(text: "newer", createdAt: Date(timeIntervalSince1970: 2000))
        appState.history.add(older, limit: 100)
        appState.history.add(newer, limit: 100)
        let result = appState.historyItems
        #expect(result[0].text == "newer")
        #expect(result[1].text == "older")
    }

    @Test func favoriteItemsFiltersByTab() {
        let appState = makeTestAppState()
        appState.configManager.load()
        appState.history.add(makeItem(text: "fav", favoriteTabs: ["Favorites"]), limit: 100)
        appState.history.add(makeItem(text: "not fav"), limit: 100)
        let favorites = appState.favoriteItems(for: "Favorites")
        #expect(favorites.count == 1)
        #expect(favorites[0].text == "fav")
    }
}
