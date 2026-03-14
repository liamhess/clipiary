import AppKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let history: HistoryStore
    private let settings: AppSettings
    private var lastCopyOnSelectText: String?
    private var lastCopyOnSelectAt = Date.distantPast
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

    func consumeCopyOnSelectSnapshot(_ snapshot: SelectionSnapshot) {
        guard settings.isCopyOnSelectEnabled else {
            return
        }

        if let text = snapshot.selectedText {
            registerCopyOnSelect(text: text, snapshot: snapshot, writeToPasteboard: true)
            return
        }

        if shouldTryAnkiFallback(for: snapshot), let text = attemptAnkiShortcutFallback() {
            registerCopyOnSelect(text: text, snapshot: snapshot, writeToPasteboard: false)
        }
    }

    func restore(_ item: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(item.text, forType: .string) else {
            return
        }

        suppressNextClipboardChange = true
    }

    private func registerCopyOnSelect(text: String, snapshot: SelectionSnapshot, writeToPasteboard: Bool) {
        guard !settings.ignores(bundleID: snapshot.bundleID) else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= settings.minimumSelectionLength else {
            return
        }

        let cooldown = Double(settings.copyOnSelectCooldownMilliseconds) / 1_000
        guard Date().timeIntervalSince(lastCopyOnSelectAt) >= cooldown else {
            return
        }

        guard lastCopyOnSelectText != text else {
            return
        }

        if writeToPasteboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                return
            }
        }

        suppressNextClipboardChange = true
        let item = HistoryItem(
            text: text,
            source: .copyOnSelect,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID
        )
        history.add(item, limit: settings.historyLimit)
        lastCopyOnSelectText = text
        lastCopyOnSelectAt = .now
    }

    private func shouldTryAnkiFallback(for snapshot: SelectionSnapshot) -> Bool {
        guard let bundleID = snapshot.bundleID else {
            return false
        }

        guard bundleID.hasPrefix("net.ankiweb.") || snapshot.appName == "Anki" else {
            return false
        }

        if snapshot.failureReason == "Secure text field" || snapshot.failureReason == "No frontmost app" {
            return false
        }

        let cooldown = Double(settings.copyOnSelectCooldownMilliseconds) / 1_000
        return Date().timeIntervalSince(lastCopyOnSelectAt) >= cooldown
    }

    private func attemptAnkiShortcutFallback(timeout: TimeInterval = 0.4) -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        guard postCommandC() else {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if pasteboard.changeCount != previousChangeCount,
               let text = pasteboard.string(forType: .string) {
                return text
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        } while Date() < deadline

        return nil
    }

    private func postCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        let commandKey: CGKeyCode = 55
        let cKey: CGKeyCode = 8

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true),
            let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        else {
            return false
        }

        cDown.flags = .maskCommand
        cUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}
