import AppKit
import CryptoKit
import Foundation

@MainActor
final class CaptureCoordinator {
    private let history: HistoryStore
    private let settings: AppSettings
    private var lastCopyOnSelectText: String?
    private var lastCopyOnSelectAt = Date.distantPast
    private var suppressNextClipboardChange = false
    private var pasteMonitor: Any?

    init(history: HistoryStore, settings: AppSettings) {
        self.history = history
        self.settings = settings
    }

    func consumeClipboardText(_ text: String, app: NSRunningApplication?, rtfData: Data? = nil, htmlData: String? = nil) {
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
                bundleID: app?.bundleIdentifier,
                isMonospace: settings.isTerminalApp(bundleID: app?.bundleIdentifier),
                rtfData: rtfData,
                htmlData: htmlData
            ),
            limit: settings.historyLimit
        )
    }

    func consumeClipboardImage(_ pngData: Data, app: NSRunningApplication?) {
        guard settings.isClipboardMonitoringEnabled else {
            return
        }

        if suppressNextClipboardChange {
            suppressNextClipboardChange = false
            return
        }

        guard !settings.ignores(bundleID: app?.bundleIdentifier) else {
            return
        }

        let hash = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()

        var description = "Image"
        if let image = NSImage(data: pngData), let rep = image.representations.first {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > 0 && h > 0 {
                description = "Image \(w)\u{00D7}\(h)"
            }
        }

        let fileName = "\(UUID().uuidString).png"
        history.saveImageData(pngData, fileName: fileName)

        let item = HistoryItem(
            text: description,
            source: .clipboard,
            appName: app?.localizedName ?? "Unknown",
            bundleID: app?.bundleIdentifier,
            imageFileName: fileName,
            imageHash: hash
        )
        history.add(item, limit: settings.historyLimit)
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

    func restore(_ item: HistoryItem, plainTextOnly: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if item.isImage, let image = history.loadImage(for: item) {
            pasteboard.writeObjects([image])
        } else if !plainTextOnly, let rtfData = item.rtfData {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(rtfData, forType: .rtf)
            pasteboardItem.setString(item.text, forType: .string)
            pasteboard.writeObjects([pasteboardItem])
        } else if !plainTextOnly, let htmlData = item.htmlData {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(htmlData, forType: .html)
            pasteboardItem.setString(item.text, forType: .string)
            pasteboard.writeObjects([pasteboardItem])
        } else {
            guard pasteboard.setString(item.text, forType: .string) else {
                return
            }
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
            bundleID: snapshot.bundleID,
            isMonospace: settings.isTerminalApp(bundleID: snapshot.bundleID)
        )
        history.add(item, limit: settings.historyLimit)
        history.evictUnpastedCopyOnSelect(limit: settings.copyOnSelectBufferLimit)
        lastCopyOnSelectText = text
        lastCopyOnSelectAt = .now
    }

    func startPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 9 = V, check for Cmd modifier
            guard event.keyCode == 9, event.modifierFlags.contains(.command) else { return }
            Task { @MainActor [weak self] in
                self?.markClipboardContentAsPasted()
            }
        }
    }

    private func markClipboardContentAsPasted() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        if let item = history.items.first(where: {
            $0.source == .copyOnSelect && !$0.wasPasted && $0.text == text
        }) {
            history.markAsPasted(item)
        }
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
        postCommandKey(vKey: 8)
    }

    @discardableResult
    private func postCommandKey(vKey: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        let commandKey: CGKeyCode = 55

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}
