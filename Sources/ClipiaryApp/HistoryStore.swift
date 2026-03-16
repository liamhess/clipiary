import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    var searchQuery = ""

    private let fileManager: FileManager
    private let storageURL: URL
    private let imagesDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipiaryDir = appSupport.appending(path: "Clipiary")
        storageURL = clipiaryDir.appending(path: "history.json")
        imagesDirectoryURL = clipiaryDir.appending(path: "images")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var filteredItems: [HistoryItem] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return recencyOrderedItems(items)
        }

        return recencyOrderedItems(items).filter { item in
            item.text.localizedCaseInsensitiveContains(normalizedQuery) ||
            item.appName.localizedCaseInsensitiveContains(normalizedQuery) ||
            (item.bundleID?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        let decodedItems = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
        items = recencyOrderedItems(decodedItems)
    }

    func saveImageData(_ data: Data, fileName: String) {
        try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        try? data.write(to: imagesDirectoryURL.appending(path: fileName), options: .atomic)
    }

    func loadImage(for item: HistoryItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let url = imagesDirectoryURL.appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    func add(_ item: HistoryItem, limit: Int) {
        let duplicateIndex: Int?
        if item.isImage {
            duplicateIndex = items.firstIndex(where: {
                $0.imageHash != nil && $0.imageHash == item.imageHash && $0.bundleID == item.bundleID
            })
        } else {
            duplicateIndex = items.firstIndex(where: {
                !$0.isImage && $0.text == item.text && $0.bundleID == item.bundleID
            })
        }

        if let duplicateIndex {
            var existing = items.remove(at: duplicateIndex)
            existing.createdAt = item.createdAt
            existing.source = item.source
            existing.appName = item.appName
            existing.bundleID = item.bundleID
            // For duplicate images, keep existing file and delete the new one
            if item.isImage, let newFile = item.imageFileName, newFile != existing.imageFileName {
                deleteImageFileNamed(newFile)
            }
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }

        trim(limit: limit)
        persist()
    }

    func delete(_ item: HistoryItem) {
        deleteImageFile(for: item)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clearNonFavorites() {
        for item in items where item.favoriteTabs.isEmpty {
            deleteImageFile(for: item)
        }
        items.removeAll { $0.favoriteTabs.isEmpty }
        persist()
    }

    func toggleFavoriteTab(_ item: HistoryItem, tabName: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        if items[index].favoriteTabs.contains(tabName) {
            items[index].favoriteTabs.remove(tabName)
        } else {
            items[index].favoriteTabs.insert(tabName)
        }
        persist()
    }

    func toggleMonospace(_ item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index].isMonospace.toggle()
        persist()
    }

    func seedEntries(for tabConfig: FavoritesTabConfig) {
        guard let entries = tabConfig.entries else { return }
        for entry in entries {
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let isMonospace = entry.monospace ?? false
            if let existingIndex = items.firstIndex(where: { $0.text == trimmed }) {
                items[existingIndex].favoriteTabs.insert(tabConfig.name)
                if isMonospace {
                    items[existingIndex].isMonospace = true
                }
            } else {
                let item = HistoryItem(
                    text: trimmed,
                    source: .restored,
                    appName: "Config",
                    bundleID: nil,
                    favoriteTabs: [tabConfig.name],
                    isMonospace: isMonospace
                )
                items.insert(item, at: 0)
            }
        }
        items = recencyOrderedItems(items)
        persist()
    }

    func moveToTop(_ item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index].createdAt = Date()
        items = recencyOrderedItems(items)
        persist()
    }

    func enforceLimit(_ limit: Int) {
        trim(limit: limit)
        persist()
    }

    private func trim(limit: Int) {
        let favorites = items.filter { !$0.favoriteTabs.isEmpty }
        let nonFavorites = recencyOrderedItems(items.filter { $0.favoriteTabs.isEmpty })
        let retainedItems = favorites + Array(nonFavorites.prefix(max(0, limit - favorites.count)))
        let retainedIDs = Set(retainedItems.map(\.id))
        for item in items where !retainedIDs.contains(item.id) {
            deleteImageFile(for: item)
        }
        items = recencyOrderedItems(retainedItems)
    }

    private func recencyOrderedItems(_ source: [HistoryItem]) -> [HistoryItem] {
        source.sorted {
            return $0.createdAt > $1.createdAt
        }
    }

    private func deleteImageFile(for item: HistoryItem) {
        guard let fileName = item.imageFileName else { return }
        deleteImageFileNamed(fileName)
    }

    private func deleteImageFileNamed(_ fileName: String) {
        try? fileManager.removeItem(at: imagesDirectoryURL.appending(path: fileName))
    }

    private func persist() {
        let directory = storageURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(items) else {
            return
        }

        try? data.write(to: storageURL, options: .atomic)
    }
}
