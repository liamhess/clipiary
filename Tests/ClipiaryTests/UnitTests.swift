import Foundation
import SwiftUI
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
    let themeManager = ThemeManager(storageDirectory: tempDir)
    return AppState(
        settings: settings,
        history: history,
        configManager: configManager,
        permissionManager: permissionManager,
        inputMonitoringPermissionManager: InputMonitoringPermissionManager(),
        themeManager: themeManager
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
    pasteCount: Int = 0,
    snippetDescription: String? = nil
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
        pasteCount: pasteCount,
        snippetDescription: snippetDescription
    )
}

@MainActor
func makeCaptureCoordinator(
    store: HistoryStore? = nil,
    settings: AppSettings? = nil
) -> (CaptureCoordinator, HistoryStore, AppSettings) {
    let resolvedStore: HistoryStore
    if let store {
        resolvedStore = store
    } else {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        resolvedStore = HistoryStore(storageDirectory: dir)
    }

    let resolvedSettings: AppSettings
    if let settings {
        resolvedSettings = settings
    } else {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        resolvedSettings = AppSettings(defaults: defaults)
    }

    return (CaptureCoordinator(history: resolvedStore, settings: resolvedSettings), resolvedStore, resolvedSettings)
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
            pasteCount: 5,
            snippetDescription: "my snippet"
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
        #expect(decoded.snippetDescription == "my snippet")
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
        #expect(settings.isCopyOnSelectSmartPasteEnabled == false)
    }

    @Test func persistsChanges() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = 500
        settings.isCopyOnSelectSmartPasteEnabled = true

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.historyLimit == 500)
        #expect(settings2.isCopyOnSelectSmartPasteEnabled == true)
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

    @Test func autoMonospaceFromTerminalsDefaultsToTrue() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.autoMonospaceFromTerminals == true)
        #expect(settings.terminalBundleIDs == AppSettings.defaultTerminalBundleIDsString)
    }

    @Test func isTerminalAppMatchesDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.isTerminalApp(bundleID: "com.apple.Terminal") == true)
        #expect(settings.isTerminalApp(bundleID: "com.googlecode.iterm2") == true)
        #expect(settings.isTerminalApp(bundleID: "com.mitchellh.ghostty") == true)
        #expect(settings.isTerminalApp(bundleID: "com.microsoft.VSCode") == true)
        #expect(settings.isTerminalApp(bundleID: "com.jetbrains.goland") == true)
        #expect(settings.isTerminalApp(bundleID: "com.example.other") == false)
        #expect(settings.isTerminalApp(bundleID: nil) == false)
    }

    @Test func isTerminalAppReturnsFalseWhenDisabled() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.autoMonospaceFromTerminals = false
        #expect(settings.isTerminalApp(bundleID: "com.apple.Terminal") == false)
    }

    @Test func isTerminalAppMatchesCustomEntry() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.terminalBundleIDs += ", com.example.term"
        #expect(settings.isTerminalApp(bundleID: "com.example.term") == true)
        #expect(settings.isTerminalApp(bundleID: "com.apple.Terminal") == true)
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

    @Test func separatorsInFavoritesDoNotReduceNonFavoritesCap() {
        let store = makeTempStore()
        let separator = HistoryItem(text: "", source: .restored, appName: "", bundleID: nil, favoriteTabs: ["Favorites"], isSeparator: true)
        store.add(separator, limit: 5)
        for i in 0..<5 {
            store.add(makeItem(text: "item \(i)"), limit: 5)
        }
        let nonFavorites = store.items.filter { $0.favoriteTabs.isEmpty }
        #expect(nonFavorites.count == 5)
    }

    @Test func persistAndLoad() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store1 = HistoryStore(storageDirectory: dir)
        store1.add(makeItem(text: "persisted"), limit: 100)
        store1.flush()

        let store2 = HistoryStore(storageDirectory: dir)
        store2.load()
        #expect(store2.items.count == 1)
        #expect(store2.items[0].text == "persisted")
    }

    @Test func setAndClearSnippetDescription() {
        let store = makeTempStore()
        let item = makeItem(text: "snippet")
        store.add(item, limit: 100)

        store.setSnippetDescription("my description", for: store.items[0])
        #expect(store.items[0].snippetDescription == "my description")

        store.setSnippetDescription("  ", for: store.items[0])
        #expect(store.items[0].snippetDescription == nil)

        store.setSnippetDescription("trimmed  ", for: store.items[0])
        #expect(store.items[0].snippetDescription == "trimmed")
    }

    @Test func collapsesGrowingCopyOnSelectChainIntoSingleItem() {
        let store = makeTempStore()
        let (coordinator, _, settings) = makeCaptureCoordinator(store: store)
        settings.isCopyOnSelectEnabled = true
        settings.copyOnSelectCooldownMilliseconds = 0

        let snapshot = SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: nil,
            selectionReadable: true,
            failureReason: nil
        )

        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            role: snapshot.role,
            subrole: snapshot.subrole,
            selectedText: "hel",
            selectionReadable: snapshot.selectionReadable,
            failureReason: snapshot.failureReason
        ))
        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            role: snapshot.role,
            subrole: snapshot.subrole,
            selectedText: "hell",
            selectionReadable: snapshot.selectionReadable,
            failureReason: snapshot.failureReason
        ))
        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            role: snapshot.role,
            subrole: snapshot.subrole,
            selectedText: "hello",
            selectionReadable: snapshot.selectionReadable,
            failureReason: snapshot.failureReason
        ))

        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hello")
        #expect(store.items[0].source == .copyOnSelect)
    }

    @Test func collapsesShrinkingCopyOnSelectChainIntoSingleItem() {
        let store = makeTempStore()
        let (coordinator, _, settings) = makeCaptureCoordinator(store: store)
        settings.isCopyOnSelectEnabled = true
        settings.copyOnSelectCooldownMilliseconds = 0

        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: "hello",
            selectionReadable: true,
            failureReason: nil
        ))
        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: "hell",
            selectionReadable: true,
            failureReason: nil
        ))

        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hell")
    }

    @Test func keepsCopyOnSelectChainsSeparateAcrossApps() {
        let store = makeTempStore()
        let (coordinator, _, settings) = makeCaptureCoordinator(store: store)
        settings.isCopyOnSelectEnabled = true
        settings.copyOnSelectCooldownMilliseconds = 0

        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: "hello",
            selectionReadable: true,
            failureReason: nil
        ))
        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Notes",
            bundleID: "com.apple.Notes",
            role: nil,
            subrole: nil,
            selectedText: "hello world",
            selectionReadable: true,
            failureReason: nil
        ))

        #expect(store.items.count == 2)
    }

    @Test func keepsNonPrefixCopyOnSelectChangesAsDistinctItems() {
        let store = makeTempStore()
        let (coordinator, _, settings) = makeCaptureCoordinator(store: store)
        settings.isCopyOnSelectEnabled = true
        settings.copyOnSelectCooldownMilliseconds = 0

        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: "hello",
            selectionReadable: true,
            failureReason: nil
        ))
        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            role: nil,
            subrole: nil,
            selectedText: "world",
            selectionReadable: true,
            failureReason: nil
        ))

        #expect(store.items.count == 2)
        #expect(Set(store.items.map(\.text)) == ["hello", "world"])
    }

    @Test func doesNotReusePastedCopyOnSelectItemAsChainTarget() {
        let store = makeTempStore()
        let item = makeItem(
            text: "hel",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )
        store.add(item, limit: 100)
        store.markAsPasted(store.items[0])

        let replacement = HistoryItem(
            text: "hello",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )

        let didReplace = store.replaceLatestTransientCopyOnSelectChain(with: replacement)

        #expect(didReplace == false)
        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hel")
        #expect(store.items[0].wasPasted == true)
    }

    @Test func collapsesSlowCopyOnSelectGrowthWithoutRecencyLimit() {
        let store = makeTempStore()
        let older = HistoryItem(
            text: "hel",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date(timeIntervalSinceNow: -60)
        )
        store.add(older, limit: 100)

        let replacement = HistoryItem(
            text: "hello",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )

        let didReplace = store.replaceLatestTransientCopyOnSelectChain(with: replacement)

        #expect(didReplace == true)
        #expect(store.items.count == 1)
        #expect(store.items[0].text == "hello")
    }

    @Test func onlyMatchesLatestTransientChainItemForSameApp() {
        let store = makeTempStore()
        store.add(HistoryItem(
            text: "hel",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date(timeIntervalSinceNow: -10)
        ), limit: 100)
        store.add(HistoryItem(
            text: "hello there",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date()
        ), limit: 100)

        let replacement = HistoryItem(
            text: "hello",
            source: .copyOnSelect,
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )

        let didReplace = store.replaceLatestTransientCopyOnSelectChain(with: replacement)

        #expect(didReplace == false)
        #expect(store.items.count == 2)
        #expect(store.items[0].text == "hello there")
        #expect(store.items[1].text == "hel")
    }
}

@MainActor
@Suite struct CaptureCoordinatorTests {
    @Test func smartPasteRestoresPreviousClipboardOnlyForExactSelectedCopyOnSelectText() {
        let (coordinator, _, settings) = makeCaptureCoordinator()
        settings.isCopyOnSelectSmartPasteEnabled = true

        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "selected",
            previousClipboard: ClipboardSnapshot(text: "previous", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 42
        )

        let shouldRestore = coordinator.shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: SelectionSnapshot(
                appName: "Notes",
                bundleID: "com.apple.Notes",
                role: nil,
                subrole: nil,
                selectedText: "selected",
                selectionReadable: true,
                failureReason: nil
            ),
            currentClipboardText: "selected",
            currentPasteboardChangeCount: 42
        )

        #expect(shouldRestore == true)
    }

    @Test func smartPasteDoesNotRestoreWhenClipboardOwnershipChanged() {
        let (coordinator, _, settings) = makeCaptureCoordinator()
        settings.isCopyOnSelectSmartPasteEnabled = true

        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "selected",
            previousClipboard: ClipboardSnapshot(text: "previous", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 42
        )

        let shouldRestore = coordinator.shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: SelectionSnapshot(
                appName: "Notes",
                bundleID: "com.apple.Notes",
                role: nil,
                subrole: nil,
                selectedText: "selected",
                selectionReadable: true,
                failureReason: nil
            ),
            currentClipboardText: "selected",
            currentPasteboardChangeCount: 43
        )

        #expect(shouldRestore == false)
    }

    @Test func smartPasteDoesNotRestoreWhenSelectionDiffersFromClipboard() {
        let (coordinator, _, settings) = makeCaptureCoordinator()
        settings.isCopyOnSelectSmartPasteEnabled = true

        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "selected",
            previousClipboard: ClipboardSnapshot(text: "previous", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 42
        )

        let shouldRestore = coordinator.shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: SelectionSnapshot(
                appName: "Notes",
                bundleID: "com.apple.Notes",
                role: nil,
                subrole: nil,
                selectedText: "other",
                selectionReadable: true,
                failureReason: nil
            ),
            currentClipboardText: "selected",
            currentPasteboardChangeCount: 42
        )

        #expect(shouldRestore == false)
    }

    @Test func smartPasteDoesNotRestoreWhenDisabled() {
        let (coordinator, _, settings) = makeCaptureCoordinator()
        settings.isCopyOnSelectSmartPasteEnabled = false

        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "selected",
            previousClipboard: ClipboardSnapshot(text: "previous", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 42
        )

        let shouldRestore = coordinator.shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: SelectionSnapshot(
                appName: "Notes",
                bundleID: "com.apple.Notes",
                role: nil,
                subrole: nil,
                selectedText: "selected",
                selectionReadable: true,
                failureReason: nil
            ),
            currentClipboardText: "selected",
            currentPasteboardChangeCount: 42
        )

        #expect(shouldRestore == false)
    }

    @Test func latestCopyOnSelectOverwriteBecomesSmartPasteFallback() {
        let (coordinator, _, settings) = makeCaptureCoordinator()
        settings.isCopyOnSelectEnabled = true
        settings.isCopyOnSelectSmartPasteEnabled = true
        settings.copyOnSelectCooldownMilliseconds = 0

        coordinator.consumeCopyOnSelectSnapshot(SelectionSnapshot(
            appName: "Notes",
            bundleID: "com.apple.Notes",
            role: nil,
            subrole: nil,
            selectedText: "first",
            selectionReadable: true,
            failureReason: nil
        ))
        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "first",
            previousClipboard: ClipboardSnapshot(text: "first", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 2
        )

        coordinator.rememberCopyOnSelectClipboardOwnership(
            text: "second",
            previousClipboard: ClipboardSnapshot(text: "first", rtfData: nil, htmlData: nil, pngData: nil),
            changeCount: 3
        )

        let shouldRestore = coordinator.shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: SelectionSnapshot(
                appName: "Notes",
                bundleID: "com.apple.Notes",
                role: nil,
                subrole: nil,
                selectedText: "second",
                selectionReadable: true,
                failureReason: nil
            ),
            currentClipboardText: "second",
            currentPasteboardChangeCount: 3
        )

        #expect(shouldRestore == true)
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

    @Test func filteredItemsMatchesSnippetDescription() {
        let appState = makeTestAppState()
        let item = makeItem(text: "some text", snippetDescription: "my API key")
        appState.history.add(item, limit: 100)
        appState.history.add(makeItem(text: "other text"), limit: 100)
        appState.searchQuery = "API"
        let results = appState.filteredItems()
        #expect(results.count == 1)
        #expect(results[0].snippetDescription == "my API key")
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

    @Test func startRestoresMissingTabsFromHistory() {
        let appState = makeTestAppState()
        // Pre-populate history with items assigned to custom tabs
        appState.history.add(makeItem(text: "snippet", favoriteTabs: ["Snippets"]), limit: 100)
        appState.history.add(makeItem(text: "cmd", favoriteTabs: ["Shell", "Snippets"]), limit: 100)

        // start() loads config (no config.json → default "Favorites") then restores missing tabs
        appState.start()

        let tabNames = appState.allTabs.map(\.id)
        #expect(tabNames.contains("fav:Snippets"))
        #expect(tabNames.contains("fav:Shell"))
    }
}

// MARK: - Theme Tests

@MainActor
@Suite struct ThemeTests {
    @Test func defaultThemeRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Theme.default)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == Theme.default)
    }

    @Test func partialThemeDecodesWithDefaults() throws {
        let json = """
        { "id": "minimal", "name": "Minimal" }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.id == "minimal")
        #expect(theme.name == "Minimal")
        #expect(theme.options == Theme.Options.default)
        #expect(theme.fills == Theme.Fills.default)
        #expect(theme.colors == Theme.Colors.default)
        #expect(theme.borders == Theme.Borders.default)
        #expect(theme.effects == Theme.Effects.default)
        #expect(theme.cornerRadii == Theme.CornerRadii.default)
        #expect(theme.spacing == Theme.Spacing.default)
    }

    @Test func partialColorsDecodesWithDefaults() throws {
        let json = """
        { "id": "custom", "name": "Custom", "colors": { "accent": "#FF0000" } }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.colors.accent == "#FF0000")
        #expect(theme.colors.cardStroke == Theme.Colors.default.cardStroke)
    }

    @Test func solidFillDecodesFromJSON() throws {
        let json = """
        { "id": "t", "name": "T", "fills": { "panel": { "color": "#FF0000", "opacity": 0.5 } } }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.fills.panel.color == "#FF0000")
        #expect(theme.fills.panel.opacity == 0.5)
        #expect(theme.fills.panel.gradient == nil)
    }

    @Test func gradientFillDecodesFromJSON() throws {
        let json = """
        { "id": "t", "name": "T", "fills": { "panel": { "gradient": ["#FF0000", "#0000FF"], "from": "top", "to": "bottom" } } }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.fills.panel.gradient == ["#FF0000", "#0000FF"])
        #expect(theme.fills.panel.from == "top")
        #expect(theme.fills.panel.to == "bottom")
        #expect(theme.fills.panel.color == nil)
    }

    @Test func bordersDecodeFromJSON() throws {
        let json = """
        { "id": "t", "name": "T", "borders": { "panel": { "color": "#FF0000", "width": 2, "opacity": 0.5 } } }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.borders.panel?.color == "#FF0000")
        #expect(theme.borders.panel?.width == 2)
        #expect(theme.borders.panel?.opacity == 0.5)
        #expect(theme.borders.selectedRow == nil)
    }

    @Test func effectsDecodeFromJSON() throws {
        let json = """
        { "id": "t", "name": "T", "effects": { "selectedRowGlow": { "color": "#FF0000", "radius": 10, "opacity": 0.3 } } }
        """
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        #expect(theme.effects.selectedRowGlow?.color == "#FF0000")
        #expect(theme.effects.selectedRowGlow?.radius == 10)
        #expect(theme.effects.panelGlow == nil)
    }

    @Test func resolvedGlowReturnsNilWhenNotSet() {
        let theme = Theme.default
        #expect(theme.resolvedSelectedRowGlow == nil)
        #expect(theme.resolvedPanelGlow == nil)
    }

    @Test func resolvedBorderIsNotVisibleByDefault() {
        let theme = Theme.default
        #expect(!theme.resolvedPanelBorder.isVisible)
        #expect(!theme.resolvedSelectedRowBorder.isVisible)
    }

    @Test func resolvedCardBorderIsVisibleByDefault() {
        let theme = Theme.default
        #expect(theme.resolvedCardBorder.isVisible)
    }

    @Test func hexColorParsing() {
        #expect(Color(hex: "#FF0000") != nil)
        #expect(Color(hex: "#00FF00FF") != nil)
        #expect(Color(hex: nil) == nil)
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "red") == nil)
        #expect(Color(hex: "#ZZZ") == nil)
    }

    @Test func resolvedAccentUsesSystemWhenFlagSet() {
        var theme = Theme.default
        theme.options.useSystemAccent = true
        #expect(theme.resolvedAccent == .accentColor)
    }

    @Test func selectedThemeIDDefaultsToDefault() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.selectedThemeID == "default")
    }

    @Test func selectedThemeIDPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.selectedThemeID = "custom"

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.selectedThemeID == "custom")
    }
}

// MARK: - ThemeManager Tests

@MainActor
@Suite struct ThemeManagerTests {
    private func makeTempManager() -> (ThemeManager, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ThemeManager(storageDirectory: dir), dir)
    }

    @Test func ensureDefaultThemeCreatesFile() {
        let (manager, dir) = makeTempManager()
        manager.ensureDefaultTheme()
        let defaultURL = dir.appending(path: "themes/default.json")
        #expect(FileManager.default.fileExists(atPath: defaultURL.path))
        // All built-in themes should be written
        for theme in Theme.builtInThemes {
            let url = dir.appending(path: "themes/\(theme.id).json")
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func loadFindsThemes() {
        let (manager, _) = makeTempManager()
        manager.ensureDefaultTheme()
        manager.load()
        #expect(manager.availableThemes.count == Theme.builtInThemes.count)
        #expect(manager.availableThemes.contains { $0.id == "default" })
    }

    @Test func loadSkipsInvalidJSON() throws {
        let (manager, dir) = makeTempManager()
        manager.ensureDefaultTheme()
        let badURL = dir.appending(path: "themes/bad.json")
        try "not json".write(to: badURL, atomically: true, encoding: .utf8)
        manager.load()
        #expect(manager.availableThemes.count == Theme.builtInThemes.count)
    }

    @Test func selectThemeFallsBackToDefault() {
        let (manager, _) = makeTempManager()
        manager.ensureDefaultTheme()
        manager.load()
        manager.selectTheme(id: "nonexistent")
        #expect(manager.activeTheme == .default)
    }

    @Test func selectThemePicksCorrectTheme() throws {
        let (manager, dir) = makeTempManager()
        manager.ensureDefaultTheme()
        let custom = Theme(id: "custom", name: "Custom")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(custom)
        try data.write(to: dir.appending(path: "themes/custom.json"))
        manager.load()
        manager.selectTheme(id: "custom")
        #expect(manager.activeTheme.id == "custom")
        #expect(manager.activeTheme.name == "Custom")
    }
}
