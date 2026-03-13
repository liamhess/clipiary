import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    var searchQuery = ""

    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = appSupport.appending(path: "Clipiary/history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var filteredItems: [HistoryItem] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return orderedItems(items)
        }

        return orderedItems(items).filter { item in
            item.text.localizedCaseInsensitiveContains(normalizedQuery) ||
            item.appName.localizedCaseInsensitiveContains(normalizedQuery) ||
            (item.bundleID?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            return
        }

        items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    func add(_ item: HistoryItem, limit: Int) {
        if let duplicateIndex = items.firstIndex(where: { $0.text == item.text && $0.bundleID == item.bundleID }) {
            var existing = items.remove(at: duplicateIndex)
            existing.createdAt = item.createdAt
            existing.source = item.source
            existing.appName = item.appName
            existing.bundleID = item.bundleID
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }

        trim(limit: limit)
        persist()
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        persist()
    }

    func togglePin(_ item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index].isPinned.toggle()
        items = orderedItems(items)
        persist()
    }

    private func trim(limit: Int) {
        let pinned = items.filter(\.isPinned)
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + Array(unpinned.prefix(max(0, limit - pinned.count)))
    }

    private func orderedItems(_ source: [HistoryItem]) -> [HistoryItem] {
        source.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }

            return $0.createdAt > $1.createdAt
        }
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
