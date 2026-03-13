import AppKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let history: HistoryStore
    private let settings: AppSettings
    private var lastAutoSelectText: String?
    private var lastAutoSelectAt = Date.distantPast
    private var suppressNextClipboardChange = false

    init(history: HistoryStore, settings: AppSettings) {
        self.history = history
        self.settings = settings
    }

    func consumeClipboardText(_ text: String, app: NSRunningApplication?) {
        guard settings.isClipboardMonitoringEnabled else {
            return
        }

        if suppressNextClipboardChange {
            suppressNextClipboardChange = false
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard !settings.ignores(bundleID: app?.bundleIdentifier) else {
            return
        }

        history.add(
            HistoryItem(
                text: text,
                source: .clipboard,
                appName: app?.localizedName ?? "Unknown",
                bundleID: app?.bundleIdentifier
            ),
            limit: settings.historyLimit
        )
    }

    func consumeAutoSelectSnapshot(_ snapshot: SelectionSnapshot) {
        guard settings.isAutoSelectEnabled else {
            return
        }

        guard let text = snapshot.selectedText else {
            return
        }

        guard !settings.ignores(bundleID: snapshot.bundleID) else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= settings.minimumSelectionLength else {
            return
        }

        let cooldown = Double(settings.autoSelectCooldownMilliseconds) / 1_000
        guard Date().timeIntervalSince(lastAutoSelectAt) >= cooldown else {
            return
        }

        guard lastAutoSelectText != text else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return
        }

        suppressNextClipboardChange = true
        let item = HistoryItem(
            text: text,
            source: .autoSelect,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID
        )
        history.add(item, limit: settings.historyLimit)
        lastAutoSelectText = text
        lastAutoSelectAt = .now
    }

    func restore(_ item: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(item.text, forType: .string) else {
            return
        }

        suppressNextClipboardChange = true
    }
}
