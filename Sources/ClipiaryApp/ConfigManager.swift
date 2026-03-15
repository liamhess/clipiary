import Foundation
import Observation

struct FavoritesTabConfig: Codable, Sendable, Identifiable, Equatable {
    let name: String
    var entries: [String]?

    var id: String { name }
}

struct ClipiaryConfig: Codable, Sendable {
    var favorites: [FavoritesTabConfig]?
}

@MainActor
@Observable
final class ConfigManager {
    private(set) var favoriteTabs: [FavoritesTabConfig] = []

    private let fileManager: FileManager
    private let configURL: URL
    private let defaults: UserDefaults
    private let seededTabsKey = "seededFavoriteTabs"

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configURL = appSupport.appending(path: "Clipiary/config.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ClipiaryConfig.self, from: data),
              let tabs = config.favorites, !tabs.isEmpty else {
            favoriteTabs = [FavoritesTabConfig(name: "Favorites")]
            return
        }
        favoriteTabs = tabs
    }

    func unseededTabs() -> [FavoritesTabConfig] {
        let seeded = Set(defaults.stringArray(forKey: seededTabsKey) ?? [])
        return favoriteTabs.filter { tab in
            tab.entries != nil && !tab.entries!.isEmpty && !seeded.contains(tab.name)
        }
    }

    func markSeeded(_ tabNames: [String]) {
        var seeded = Set(defaults.stringArray(forKey: seededTabsKey) ?? [])
        for name in tabNames {
            seeded.insert(name)
        }
        defaults.set(Array(seeded), forKey: seededTabsKey)
    }

    func isSeededEntry(_ text: String, inTab tabName: String) -> Bool {
        guard let tab = favoriteTabs.first(where: { $0.name == tabName }),
              let entries = tab.entries else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }
    }
}
