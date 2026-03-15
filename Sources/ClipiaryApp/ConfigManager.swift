import Foundation
import Observation

struct FavoritesEntryConfig: Codable, Sendable, Equatable {
    let text: String
    var monospace: Bool?

    init(text: String, monospace: Bool? = nil) {
        self.text = text
        self.monospace = monospace
    }

    init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode(String.self) {
            text = plain
            monospace = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            monospace = try container.decodeIfPresent(Bool.self, forKey: .monospace)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text, monospace
    }
}

struct FavoritesTabConfig: Codable, Sendable, Identifiable, Equatable {
    let name: String
    var entries: [FavoritesEntryConfig]?

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

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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

    var tabsWithEntries: [FavoritesTabConfig] {
        favoriteTabs.filter { tab in
            tab.entries != nil && !tab.entries!.isEmpty
        }
    }

    func isSeededEntry(_ text: String, inTab tabName: String) -> Bool {
        guard let tab = favoriteTabs.first(where: { $0.name == tabName }),
              let entries = tab.entries else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }
    }
}
