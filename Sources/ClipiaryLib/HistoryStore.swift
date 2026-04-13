import AppKit
import Foundation
import Observation

private let historyPersistQueue = DispatchQueue(label: "com.clipiary.persist", qos: .utility)

@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    var searchQuery = ""
    private(set) var mutationGeneration: Int = 0

    private let fileManager: FileManager
    private let storageURL: URL
    private let imagesDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var persistTimer: Timer?

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        let clipiaryDir: URL
        if let storageDirectory {
            clipiaryDir = storageDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            clipiaryDir = appSupport.appending(path: "Clipiary")
        }
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
        mutationGeneration &+= 1
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

    func replaceLatestTransientCopyOnSelectChain(with item: HistoryItem) -> Bool {
        guard let candidateIndex = items.firstIndex(where: { existing in
            existing.source == .copyOnSelect &&
            !existing.wasPasted &&
            existing.favoriteTabs.isEmpty &&
            matchesCopyOnSelectAppIdentity(existing, appName: item.appName, bundleID: item.bundleID)
        }) else {
            return false
        }

        let existing = items.remove(at: candidateIndex)
        guard textsBelongToSameSelectionChain(existing.text, item.text) else {
            items.insert(existing, at: candidateIndex)
            return false
        }

        let replacement = HistoryItem(
            id: existing.id,
            text: item.text,
            source: .copyOnSelect,
            appName: item.appName,
            bundleID: item.bundleID,
            createdAt: item.createdAt,
            favoriteTabs: existing.favoriteTabs,
            isMonospace: item.isMonospace,
            imageFileName: existing.imageFileName,
            imageHash: existing.imageHash,
            wasPasted: existing.wasPasted,
            pasteCount: existing.pasteCount,
            shortcutKeyCode: existing.shortcutKeyCode,
            shortcutModifiers: existing.shortcutModifiers,
            sortIndex: existing.sortIndex,
            snippetDescription: existing.snippetDescription,
            isSeparator: existing.isSeparator,
            rtfData: existing.rtfData,
            htmlData: existing.htmlData
        )

        items.insert(replacement, at: 0)
        persist()
        return true
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

    func setShortcut(_ shortcut: GlobalShortcut, for item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].shortcutKeyCode = Int(shortcut.keyCode)
        items[index].shortcutModifiers = Int(shortcut.modifiers.rawValue)
        persist()
    }

    func removeShortcut(for item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].shortcutKeyCode = nil
        items[index].shortcutModifiers = nil
        persist()
    }

    func setSnippetDescription(_ description: String?, for item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].snippetDescription = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persist()
    }

    func setText(_ text: String, for item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[index].text = trimmed
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

        // Freeze favorite tab positions before bumping createdAt so the item
        // (and its neighbors) keep their custom order in every favorites tab.
        let tabs = items[index].favoriteTabs
        if !tabs.isEmpty {
            // Single pass: collect IDs of all items sharing any of the same tabs.
            var relevantIDs = Set<UUID>()
            for item in items where !item.favoriteTabs.isDisjoint(with: tabs) {
                relevantIDs.insert(item.id)
            }
            assignSortIndices(to: relevantIDs)
        }

        items[index].createdAt = Date()
        items = recencyOrderedItems(items)
        persist()
    }

    func enforceLimit(_ limit: Int) {
        trim(limit: limit)
        persist()
    }

    func markAsPasted(_ item: HistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        items[index].wasPasted = true
        items[index].pasteCount += 1
        persist()
    }

    func removeTabFromAllItems(tabName: String) {
        var changed = false
        for i in items.indices where items[i].favoriteTabs.contains(tabName) {
            items[i].favoriteTabs.remove(tabName)
            changed = true
        }
        if changed { persist() }
    }

    func renameTabInAllItems(oldName: String, newName: String) {
        var changed = false
        for i in items.indices where items[i].favoriteTabs.contains(oldName) {
            items[i].favoriteTabs.remove(oldName)
            items[i].favoriteTabs.insert(newName)
            changed = true
        }
        if changed { persist() }
    }

    /// Sorts items using explicit sortIndex when available, falling back to recency.
    /// Items with nil sortIndex come first (newest first), then items with explicit sortIndex ascending.
    func customOrderedItems(_ source: [HistoryItem]) -> [HistoryItem] {
        let withoutIndex = source.filter { $0.sortIndex == nil }.sorted { $0.createdAt > $1.createdAt }
        let withIndex = source.filter { $0.sortIndex != nil }.sorted { $0.sortIndex! < $1.sortIndex! }
        return withoutIndex + withIndex
    }

    /// Assigns explicit sortIndex values to all items in the given list that lack one.
    func assignSortIndices(to itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        // Collect the items in their current custom order
        let ordered = customOrderedItems(items.filter { itemIDs.contains($0.id) })
        for (position, orderedItem) in ordered.enumerated() {
            if let idx = items.firstIndex(where: { $0.id == orderedItem.id }) {
                items[idx].sortIndex = Double(position) * 100.0
            }
        }
        persist()
    }

    /// Moves an item to a new position within a given ordered list of items.
    func moveItem(_ itemID: UUID, toIndex destinationIndex: Int, inOrderedItems orderedItems: [HistoryItem]) {
        guard let sourceIndex = orderedItems.firstIndex(where: { $0.id == itemID }) else { return }
        guard sourceIndex != destinationIndex else { return }

        // Build the list without the dragged item
        var reordered = orderedItems
        let moved = reordered.remove(at: sourceIndex)
        let insertAt = min(destinationIndex, reordered.count)

        let newSortIndex: Double
        if reordered.isEmpty {
            newSortIndex = 0.0
        } else if insertAt == 0 {
            newSortIndex = (reordered[0].sortIndex ?? 0.0) - 100.0
        } else if insertAt >= reordered.count {
            newSortIndex = (reordered[reordered.count - 1].sortIndex ?? 0.0) + 100.0
        } else {
            let before = reordered[insertAt - 1].sortIndex ?? 0.0
            let after = reordered[insertAt].sortIndex ?? (before + 200.0)
            newSortIndex = (before + after) / 2.0
        }

        guard let itemIndex = items.firstIndex(where: { $0.id == moved.id }) else { return }
        items[itemIndex].sortIndex = newSortIndex
        persist()
    }

    /// Inserts a separator item after `anchor` in the given favorite tab.
    /// Ensures all items in the tab get explicit sort indices first, then slots
    /// the separator at the midpoint between anchor and its successor.
    func insertSeparator(_ separator: HistoryItem, after anchor: HistoryItem, inTab tabName: String) {
        // Assign stable sort indices to all existing tab items
        let tabItemIDs = Set(items.filter { $0.favoriteTabs.contains(tabName) }.map(\.id))
        assignSortIndices(to: tabItemIDs)

        // Re-read ordered items after indices are assigned
        let ordered = customOrderedItems(items.filter { $0.favoriteTabs.contains(tabName) })
        let anchorIndex = ordered.firstIndex(where: { $0.id == anchor.id }) ?? ordered.count - 1
        let anchorSort = ordered[anchorIndex].sortIndex ?? (Double(anchorIndex) * 100.0)
        let nextSort: Double
        if anchorIndex + 1 < ordered.count {
            nextSort = ordered[anchorIndex + 1].sortIndex ?? (anchorSort + 100.0)
        } else {
            nextSort = anchorSort + 100.0
        }

        var sep = separator
        sep.sortIndex = (anchorSort + nextSort) / 2.0
        items.insert(sep, at: 0)
        persist()
    }

    func evictUnpastedCopyOnSelect(limit: Int) {
        let unpasted = items
            .enumerated()
            .filter { $0.element.source == .copyOnSelect && !$0.element.wasPasted && $0.element.favoriteTabs.isEmpty }
            .sorted { $0.element.createdAt > $1.element.createdAt }

        guard unpasted.count > limit else { return }

        let toEvict = unpasted.dropFirst(limit)
        let evictIDs = Set(toEvict.map { $0.element.id })
        for entry in toEvict {
            deleteImageFile(for: entry.element)
        }
        items.removeAll { evictIDs.contains($0.id) }
        persist()
    }

    private func trim(limit: Int) {
        let favorites = items.filter { !$0.favoriteTabs.isEmpty }
        let nonFavorites = recencyOrderedItems(items.filter { $0.favoriteTabs.isEmpty })
        let nonSeparatorFavoriteCount = favorites.filter { !$0.isSeparator }.count
        let retainedItems = favorites + Array(nonFavorites.prefix(max(0, limit - nonSeparatorFavoriteCount)))
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

    private func matchesCopyOnSelectAppIdentity(_ item: HistoryItem, appName: String, bundleID: String?) -> Bool {
        if let bundleID {
            return item.bundleID == bundleID
        }

        return item.bundleID == nil && item.appName == appName
    }

    private func textsBelongToSameSelectionChain(_ lhs: String, _ rhs: String) -> Bool {
        lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }

    private func deleteImageFile(for item: HistoryItem) {
        guard let fileName = item.imageFileName else { return }
        deleteImageFileNamed(fileName)
    }

    private func deleteImageFileNamed(_ fileName: String) {
        try? fileManager.removeItem(at: imagesDirectoryURL.appending(path: fileName))
    }

    private func persist() {
        mutationGeneration &+= 1
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.writeToDisk()
            }
        }
    }

    private func writeToDisk() {
        let directory = storageURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(items) else { return }
        let url = storageURL
        historyPersistQueue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Immediately writes any pending changes to disk. Used by tests.
    func flush() {
        persistTimer?.invalidate()
        persistTimer = nil
        let directory = storageURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
