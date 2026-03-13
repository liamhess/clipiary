import Foundation

enum CaptureSource: String, Codable, Sendable {
    case clipboard
    case autoSelect
    case restored
}

struct HistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var text: String
    var source: CaptureSource
    var appName: String
    var bundleID: String?
    var createdAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        source: CaptureSource,
        appName: String,
        bundleID: String?,
        createdAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.appName = appName
        self.bundleID = bundleID
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    var displayText: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
