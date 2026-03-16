import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let settings: AppSettings
    private let captureCoordinator: CaptureCoordinator
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var changeCount: Int

    init(settings: AppSettings, captureCoordinator: CaptureCoordinator) {
        self.settings = settings
        self.captureCoordinator = captureCoordinator
        changeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    private func poll() {
        guard pasteboard.changeCount != changeCount else {
            return
        }

        changeCount = pasteboard.changeCount

        // Text takes priority when both text and image are present
        if let text = pasteboard.string(forType: .string) {
            captureCoordinator.consumeClipboardText(text, app: NSWorkspace.shared.frontmostApplication)
            return
        }

        // Fall through to image detection
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            captureCoordinator.consumeClipboardImage(pngData, app: NSWorkspace.shared.frontmostApplication)
        }
    }
}
