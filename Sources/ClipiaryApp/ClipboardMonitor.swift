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

        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        captureCoordinator.consumeClipboardText(text, app: NSWorkspace.shared.frontmostApplication)
    }
}
