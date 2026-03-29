import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import ClipiaryLib

@MainActor
@Suite struct HistoryRowViewSnapshotTests {
    @Test func plainTextRow() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "Hello, world! This is a clipboard entry.",
            appName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: true,
            pasteCountBarScheme: "ocean",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 70)))
    }

    @Test func selectedRow() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "Selected clipboard entry",
            appName: "Terminal",
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: true,
            showAppIcons: false,
            showItemDetails: true,
            pasteCountBarScheme: "ocean",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 70)))
    }

    @Test func favoriteRow() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "Favorite entry",
            appName: "Notes",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            favoriteTabs: ["Favorites"]
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: true,
            pasteCountBarScheme: "neon",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: ["Favorites"],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 70)))
    }

    @Test func monospaceRow() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "let x = 42; print(x)",
            appName: "Xcode",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            isMonospace: true
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: false,
            pasteCountBarScheme: "none",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 50)))
    }

    @Test func longTextRow() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "This is a very long clipboard entry that should be truncated after two lines to ensure the UI does not overflow with extremely lengthy text content from the clipboard.",
            appName: "Chrome",
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: true,
            pasteCountBarScheme: "sunset",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 80)))
    }

    @Test func rowWithHighPasteCount() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "Frequently pasted",
            appName: "Slack",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            pasteCount: 25
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 25,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: false,
            pasteCountBarScheme: "ember",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 50)))
    }

    @Test func favoriteRowWithMultipleTabs() {
        let appState = makeTestAppState()
        let item = makeItem(
            text: "Multi-tab favorite",
            appName: "Notes",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            favoriteTabs: ["Favorites", "Snippets"]
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: false,
            pasteCountBarScheme: "none",
            singleFavoriteTab: false,
            singleFavoriteTabName: nil,
            showingFavoriteTabPicker: false,
            favoriteTabNames: ["Favorites", "Snippets"],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 50)))
    }

    @Test func searchHighlightedRow() {
        let appState = makeTestAppState()
        appState.searchQuery = "hello"
        let item = makeItem(
            text: "Say Hello World",
            appName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            snippetDescription: "greeting hello"
        )
        let view = HistoryRowView(
            item: item,
            maxPasteCount: 10,
            isSelected: false,
            showAppIcons: false,
            showItemDetails: true,
            pasteCountBarScheme: "none",
            singleFavoriteTab: true,
            singleFavoriteTabName: "Favorites",
            showingFavoriteTabPicker: false,
            favoriteTabNames: [],
            itemLineLimit: 2,
            appState: appState
        )
        .environment(appState)
        .environment(\.theme, .default)
        .frame(width: 350)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 350, height: 90)))
    }
}

@MainActor
@Suite struct SettingsViewSnapshotTests {
    @Test func settingsView() {
        let appState = makeTestAppState()
        let view = SettingsView()
            .environment(appState)
            .environment(\.theme, .default)
            .frame(width: 540, height: 490)

        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: .init(width: 540, height: 490)))
    }
}
