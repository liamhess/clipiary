import AppKit
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
    var isMonospace: Bool
    var imageFileName: String?
    var imageHash: String?
    var wasPasted: Bool
    var pasteCount: Int
    var shortcutKeyCode: Int?
    var shortcutModifiers: Int?
    var sortIndex: Double?
    var snippetDescription: String?
    var isSeparator: Bool
    var rtfData: Data?
    var htmlData: String?
    let displayText: String

    init(
        id: UUID = UUID(),
        text: String,
        source: CaptureSource,
        appName: String,
        bundleID: String?,
        createdAt: Date = .now,
        favoriteTabs: Set<String> = [],
        isMonospace: Bool = false,
        imageFileName: String? = nil,
        imageHash: String? = nil,
        wasPasted: Bool = false,
        pasteCount: Int = 0,
        shortcutKeyCode: Int? = nil,
        shortcutModifiers: Int? = nil,
        sortIndex: Double? = nil,
        snippetDescription: String? = nil,
        isSeparator: Bool = false,
        rtfData: Data? = nil,
        htmlData: String? = nil
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.appName = appName
        self.bundleID = bundleID
        self.createdAt = createdAt
        self.favoriteTabs = favoriteTabs
        self.isMonospace = isMonospace
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.wasPasted = wasPasted
        self.pasteCount = pasteCount
        self.shortcutKeyCode = shortcutKeyCode
        self.shortcutModifiers = shortcutModifiers
        self.sortIndex = sortIndex
        self.snippetDescription = snippetDescription
        self.isSeparator = isSeparator
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.displayText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isImage: Bool {
        imageFileName != nil
    }

    var isFavorite: Bool {
        !favoriteTabs.isEmpty
    }

    var globalShortcut: GlobalShortcut? {
        guard let keyCode = shortcutKeyCode, let modifiers = shortcutModifiers else { return nil }
        return GlobalShortcut(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
    }

}

extension HistoryItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, source, appName, bundleID, createdAt
        case favoriteTabs
        case isFavorite // legacy key for decoding only
        case monospace
        case imageFileName, imageHash
        case wasPasted
        case pasteCount
        case shortcutKeyCode, shortcutModifiers
        case sortIndex
        case snippetDescription
        case isSeparator
        case rtfData
        case htmlData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decode(CaptureSource.self, forKey: .source)
        appName = try container.decode(String.self, forKey: .appName)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isMonospace = (try? container.decode(Bool.self, forKey: .monospace)) ?? false
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        wasPasted = (try? container.decode(Bool.self, forKey: .wasPasted)) ?? false
        pasteCount = (try? container.decode(Int.self, forKey: .pasteCount)) ?? 0
        shortcutKeyCode = try container.decodeIfPresent(Int.self, forKey: .shortcutKeyCode)
        shortcutModifiers = try container.decodeIfPresent(Int.self, forKey: .shortcutModifiers)
        sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex)
        snippetDescription = try container.decodeIfPresent(String.self, forKey: .snippetDescription)
        isSeparator = (try? container.decode(Bool.self, forKey: .isSeparator)) ?? false
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try container.decodeIfPresent(String.self, forKey: .htmlData)

        if let tabs = try? container.decode(Set<String>.self, forKey: .favoriteTabs) {
            favoriteTabs = tabs
        } else if let legacy = try? container.decode(Bool.self, forKey: .isFavorite), legacy {
            favoriteTabs = ["Favorites"]
        } else {
            favoriteTabs = []
        }
        displayText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        try container.encode(isMonospace, forKey: .monospace)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(imageHash, forKey: .imageHash)
        try container.encode(wasPasted, forKey: .wasPasted)
        try container.encode(pasteCount, forKey: .pasteCount)
        try container.encodeIfPresent(shortcutKeyCode, forKey: .shortcutKeyCode)
        try container.encodeIfPresent(shortcutModifiers, forKey: .shortcutModifiers)
        try container.encodeIfPresent(sortIndex, forKey: .sortIndex)
        try container.encodeIfPresent(snippetDescription, forKey: .snippetDescription)
        try container.encode(isSeparator, forKey: .isSeparator)
        try container.encodeIfPresent(rtfData, forKey: .rtfData)
        try container.encodeIfPresent(htmlData, forKey: .htmlData)
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
