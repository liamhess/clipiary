import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settings = AppSettings()
    let history = HistoryStore()
    let permissionManager = AccessibilityPermissionManager()

    @ObservationIgnored private let captureCoordinator: CaptureCoordinator
    @ObservationIgnored private let clipboardMonitor: ClipboardMonitor
    @ObservationIgnored private let autoSelectEngine: AutoSelectEngine

    private init() {
        let captureCoordinator = CaptureCoordinator(history: history, settings: settings)
        self.captureCoordinator = captureCoordinator
        self.clipboardMonitor = ClipboardMonitor(settings: settings, captureCoordinator: captureCoordinator)
        self.autoSelectEngine = AutoSelectEngine(
            settings: settings,
            permissionManager: permissionManager,
            captureCoordinator: captureCoordinator
        )
    }

    func start() {
        history.load()
        permissionManager.refreshTrust()
        clipboardMonitor.start()
        autoSelectEngine.start()
    }

    func refreshAutoSelectPermissions() {
        permissionManager.requestAccessPrompt()
        permissionManager.openPrivacySettings()
    }

    func restore(_ item: HistoryItem) {
        captureCoordinator.restore(item)
        if settings.pasteOnSelect {
            PasteService.paste()
        }
    }
}
