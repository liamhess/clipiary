import AppKit
import ApplicationServices
import CryptoKit
import Foundation

struct ClipboardSnapshot: Sendable {
    let text: String?
    let rtfData: Data?
    let htmlData: String?
    let pngData: Data?

    var isEmpty: Bool {
        text == nil && rtfData == nil && htmlData == nil && pngData == nil
    }

    static func capture(from pasteboard: NSPasteboard = .general) -> ClipboardSnapshot? {
        let text = pasteboard.string(forType: .string)
        let rtfData = pasteboard.data(forType: .rtf)
        let htmlData = pasteboard.string(forType: .html)

        var pngData: Data?
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }

        let snapshot = ClipboardSnapshot(text: text, rtfData: rtfData, htmlData: htmlData, pngData: pngData)
        return snapshot.isEmpty ? nil : snapshot
    }
}

@MainActor
final class CaptureCoordinator {
    private let history: HistoryStore
    private let settings: AppSettings
    private var lastCopyOnSelectText: String?
    private var lastCopyOnSelectAt = Date.distantPast
    private var suppressNextClipboardChange = false
    private var pasteMonitor: Any?
    private var pasteEventTap: CFMachPort?
    private var pasteEventTapRunLoopSource: CFRunLoopSource?
    private var pasteMonitorRetryTimer: Timer?
    private var clipboardBeforeCopyOnSelect: ClipboardSnapshot?
    private var copyOnSelectOwnedPasteboardText: String?
    private var copyOnSelectOwnedPasteboardChangeCount: Int?

    init(history: HistoryStore, settings: AppSettings) {
        self.history = history
        self.settings = settings
    }

    func consumeClipboardText(_ text: String, app: NSRunningApplication?, rtfData: Data? = nil, htmlData: String? = nil) {
        if suppressNextClipboardChange {
            suppressNextClipboardChange = false
            return
        }

        clearCopyOnSelectClipboardOwnership()

        guard settings.isClipboardMonitoringEnabled else {
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
        if suppressNextClipboardChange {
            suppressNextClipboardChange = false
            return
        }

        clearCopyOnSelectClipboardOwnership()

        guard settings.isClipboardMonitoringEnabled else {
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
        clearCopyOnSelectClipboardOwnership()

        let didWrite: Bool
        if item.isImage, let image = history.loadImage(for: item) {
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([image])
        } else {
            let snapshot = ClipboardSnapshot(
                text: item.text,
                rtfData: plainTextOnly ? nil : item.rtfData,
                htmlData: plainTextOnly ? nil : item.htmlData,
                pngData: nil
            )
            didWrite = writeClipboardSnapshot(snapshot, to: pasteboard)
        }

        guard didWrite else {
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
            let previousClipboard = ClipboardSnapshot.capture(from: pasteboard)
            guard writeClipboardSnapshot(ClipboardSnapshot(text: text, rtfData: nil, htmlData: nil, pngData: nil), to: pasteboard) else {
                return
            }
            rememberCopyOnSelectClipboardOwnership(text: text, previousClipboard: previousClipboard, changeCount: pasteboard.changeCount)
        } else {
            clearCopyOnSelectClipboardOwnership()
        }

        suppressNextClipboardChange = true
        let item = HistoryItem(
            text: text,
            source: .copyOnSelect,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            isMonospace: settings.isTerminalApp(bundleID: snapshot.bundleID)
        )
        if !history.replaceLatestTransientCopyOnSelectChain(with: item) {
            history.add(item, limit: settings.historyLimit)
        }
        history.evictUnpastedCopyOnSelect(limit: settings.copyOnSelectBufferLimit)
        lastCopyOnSelectText = text
        lastCopyOnSelectAt = .now
    }

    func startPasteMonitor() {
        ensurePasteMonitor()

        guard pasteMonitorRetryTimer == nil else { return }
        pasteMonitorRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ensurePasteMonitor()
            }
        }
    }

    private func ensurePasteMonitor() {
        guard pasteEventTap == nil else { return }

        if let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: Self.pasteEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            pasteEventTap = eventTap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            pasteEventTapRunLoopSource = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if let pasteMonitor {
                NSEvent.removeMonitor(pasteMonitor)
                self.pasteMonitor = nil
            }
            return
        }

        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 9 = V, check for Cmd modifier
            guard event.keyCode == 9, event.modifierFlags.contains(.command) else { return }
            Task { @MainActor [weak self] in
                self?.markClipboardContentAsPasted()
            }
        }
    }

    func rememberCopyOnSelectClipboardOwnership(text: String, previousClipboard: ClipboardSnapshot?, changeCount: Int) {
        clipboardBeforeCopyOnSelect = previousClipboard
        copyOnSelectOwnedPasteboardText = text
        copyOnSelectOwnedPasteboardChangeCount = changeCount
    }

    func shouldRestorePreviousClipboardBeforePaste(
        selectionSnapshot: SelectionSnapshot,
        currentClipboardText: String?,
        currentPasteboardChangeCount: Int
    ) -> Bool {
        guard settings.isCopyOnSelectSmartPasteEnabled else {
            return false
        }

        guard let previousClipboard = clipboardBeforeCopyOnSelect, !previousClipboard.isEmpty else {
            return false
        }

        guard let ownedText = copyOnSelectOwnedPasteboardText,
              let ownedChangeCount = copyOnSelectOwnedPasteboardChangeCount,
              ownedChangeCount == currentPasteboardChangeCount else {
            return false
        }

        guard selectionSnapshot.selectedText == ownedText,
              currentClipboardText == ownedText else {
            return false
        }

        return true
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

    private func handleCommandVPasteEvent() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if frontmostApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        attemptSmartPasteRestoreIfNeeded()
        markClipboardContentAsPasted()
    }

    private func attemptSmartPasteRestoreIfNeeded() {
        let pasteboard = NSPasteboard.general
        let selectionSnapshot = SelectionReader.read(from: NSWorkspace.shared.frontmostApplication)
        let currentClipboardText = pasteboard.string(forType: .string)

        guard shouldRestorePreviousClipboardBeforePaste(
            selectionSnapshot: selectionSnapshot,
            currentClipboardText: currentClipboardText,
            currentPasteboardChangeCount: pasteboard.changeCount
        ) else {
            if let ownedChangeCount = copyOnSelectOwnedPasteboardChangeCount,
               ownedChangeCount != pasteboard.changeCount {
                clearCopyOnSelectClipboardOwnership()
            }
            return
        }

        guard let previousClipboard = clipboardBeforeCopyOnSelect,
              writeClipboardSnapshot(previousClipboard, to: pasteboard) else {
            return
        }

        suppressNextClipboardChange = true
        clearCopyOnSelectClipboardOwnership()
    }

    private func clearCopyOnSelectClipboardOwnership() {
        clipboardBeforeCopyOnSelect = nil
        copyOnSelectOwnedPasteboardText = nil
        copyOnSelectOwnedPasteboardChangeCount = nil
    }

    @discardableResult
    private func writeClipboardSnapshot(_ snapshot: ClipboardSnapshot, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()

        if let pngData = snapshot.pngData, let image = NSImage(data: pngData) {
            return pasteboard.writeObjects([image])
        }

        let pasteboardItem = NSPasteboardItem()
        var wroteAnyValue = false

        if let rtfData = snapshot.rtfData {
            pasteboardItem.setData(rtfData, forType: .rtf)
            wroteAnyValue = true
        }

        if let htmlData = snapshot.htmlData {
            pasteboardItem.setString(htmlData, forType: .html)
            wroteAnyValue = true
        }

        if let text = snapshot.text {
            pasteboardItem.setString(text, forType: .string)
            wroteAnyValue = true
        }

        guard wroteAnyValue else {
            return false
        }

        return pasteboard.writeObjects([pasteboardItem])
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

    private static let pasteEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let coordinator = Unmanaged<CaptureCoordinator>.fromOpaque(refcon).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        MainActor.assumeIsolated {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let eventTap = coordinator.pasteEventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            case .keyDown:
                let hasCommand = flags.contains(.maskCommand)
                let hasControl = flags.contains(.maskControl)
                let hasOption = flags.contains(.maskAlternate)
                if keyCode == 9,
                   hasCommand && !hasControl && !hasOption {
                    coordinator.handleCommandVPasteEvent()
                }
            default:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
