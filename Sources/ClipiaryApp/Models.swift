import Foundation

enum CaptureSource: String, Codable, Sendable {
    case clipboard
    case copyOnSelect
    case restored
}

struct HistoryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String
    var source: CaptureSource
    var appName: String
    var bundleID: String?
    var createdAt: Date
    var favoriteTabs: Set<String>

    init(
        id: UUID = UUID(),
        text: String,
        source: CaptureSource,
        appName: String,
        bundleID: String?,
        createdAt: Date = .now,
        favoriteTabs: Set<String> = []
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.appName = appName
        self.bundleID = bundleID
        self.createdAt = createdAt
        self.favoriteTabs = favoriteTabs
    }

    var isFavorite: Bool {
        !favoriteTabs.isEmpty
    }

    var displayText: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension HistoryItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, source, appName, bundleID, createdAt
        case favoriteTabs
        case isFavorite // legacy key for decoding only
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decode(CaptureSource.self, forKey: .source)
        appName = try container.decode(String.self, forKey: .appName)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        if let tabs = try? container.decode(Set<String>.self, forKey: .favoriteTabs) {
            favoriteTabs = tabs
        } else if let legacy = try? container.decode(Bool.self, forKey: .isFavorite), legacy {
            favoriteTabs = ["Favorites"]
        } else {
            favoriteTabs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(source, forKey: .source)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(favoriteTabs, forKey: .favoriteTabs)
    }
}

struct CapturedContent {
    let text: String
    let source: CaptureSource
    let appName: String
    let bundleID: String?
    let shouldWriteToPasteboard: Bool
}

struct SelectionSnapshot {
    let appName: String
    let bundleID: String?
    let role: String?
    let subrole: String?
    let selectedText: String?
    let selectionReadable: Bool
    let failureReason: String?
}
