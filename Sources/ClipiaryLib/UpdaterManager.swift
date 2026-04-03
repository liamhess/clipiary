import AppKit
import Sparkle

@MainActor
enum UpdatePhase {
    case idle
    case checking(cancel: @MainActor () -> Void)
    case updateFound(item: SUAppcastItem, state: SPUUserUpdateState?, reply: @MainActor (SPUUserUpdateChoice) -> Void)
    case notFound(acknowledge: @MainActor () -> Void)
    case downloading(cancel: @MainActor () -> Void)
    case extracting
    case readyToInstall(reply: @MainActor (SPUUserUpdateChoice) -> Void)
    case installing
    case done(acknowledge: @MainActor () -> Void)
    case error(message: String, acknowledge: @MainActor () -> Void)
}

@MainActor @Observable
public final class UpdaterManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var driver: InAppUserDriver?

    var phase: UpdatePhase = .idle
    var downloadExpectedBytes: Int64 = 0
    var downloadReceivedBytes: Int64 = 0
    var extractionProgress: Double = 0.0
    var releaseNotesHTML: String? = nil

    var isConfigured: Bool { updater != nil }
    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }

    var updateAvailable: Bool {
        switch phase {
        case .updateFound, .readyToInstall: return true
        default: return false
        }
    }

    var showOverlay: Bool {
        if case .idle = phase { return false }
        return true
    }

    private override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let driver = InAppUserDriver()
        driver.onPhaseChange = { [weak self] phase in
            self?.phase = phase
            #if DEBUG
            if case .updateFound(let item, let state, _) = phase {
                self?.debugLastUpdateFound = (item, state)
            }
            #endif
        }
        driver.onReleaseNotes = { [weak self] html in self?.releaseNotesHTML = html }
        driver.onDownloadExpected = { [weak self] bytes in self?.downloadExpectedBytes = bytes }
        driver.onDownloadReceived = { [weak self] bytes in self?.downloadReceivedBytes += bytes }
        driver.onExtractionProgress = { [weak self] p in self?.extractionProgress = p }
        driver.onDismiss = { [weak self] in
            self?.phase = .idle
            self?.releaseNotesHTML = nil
            self?.downloadExpectedBytes = 0
            self?.downloadReceivedBytes = 0
            self?.extractionProgress = 0
        }
        self.driver = driver
        let spuUpdater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: self
        )
        do {
            try spuUpdater.start()
            self.updater = spuUpdater
        } catch {
            print("[UpdaterManager] Could not start updater: \(error)")
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func dismissOverlay() {
        switch phase {
        case .checking(let cancel):
            cancel()
            phase = .idle
        case .updateFound(_, _, let reply):
            reply(.dismiss)
            // Sparkle will call dismissUpdateInstallation which sets phase = .idle
        case .notFound(let ack):
            ack()
            phase = .idle
        case .error(_, let ack):
            ack()
            phase = .idle
        case .done(let ack):
            ack()
            phase = .idle
        case .downloading(let cancel):
            cancel()
            phase = .idle
        case .readyToInstall(let reply):
            reply(.dismiss)
        case .idle, .extracting, .installing:
            break
        }
    }

    // MARK: - SPUUpdaterDelegate

    public nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        // Phase transition is handled by InAppUserDriver; nothing extra needed here.
    }
    public nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Phase transition is handled by InAppUserDriver; nothing extra needed here.
    }

    // MARK: - Debug

    #if DEBUG
    /// Last update state seen from a real Sparkle check — used by cycleDebugPhase().
    var debugLastUpdateFound: (item: SUAppcastItem, state: SPUUserUpdateState?)?

    func cycleDebugPhase() {
        switch phase {
        case .idle:
            phase = .checking(cancel: {})
        case .checking:
            guard let fakeItem = debugFakeAppcastItem() else { break }
            let (item, state) = debugLastUpdateFound ?? (fakeItem, nil)
            phase = .updateFound(item: item, state: state, reply: { _ in })
            releaseNotesHTML = debugReleaseNotesHTML
        case .updateFound:
            downloadExpectedBytes = 3_126_236
            downloadReceivedBytes = 0
            phase = .downloading(cancel: {})
        case .downloading:
            downloadReceivedBytes = downloadExpectedBytes
            extractionProgress = 0
            phase = .extracting
        case .extracting:
            extractionProgress = min(extractionProgress + 0.35, 1.0)
            if extractionProgress >= 1.0 {
                phase = .readyToInstall(reply: { _ in })
            }
        case .readyToInstall:
            phase = .installing
        case .installing:
            phase = .done(acknowledge: {})
        case .done:
            phase = .error(message: "Something went wrong during the update.", acknowledge: {})
        case .notFound, .error:
            phase = .idle
            releaseNotesHTML = nil
            downloadExpectedBytes = 0
            downloadReceivedBytes = 0
            extractionProgress = 0
        }
    }

    private func debugFakeAppcastItem() -> SUAppcastItem? {
        let props: [String: Any] = [
            "title": "Version 99.0.0",
            "sparkle:version": "99.0.0",
            "sparkle:shortVersionString": "99.0.0",
            "enclosure": ["url": "https://example.com/Clipiary-99.0.0.zip", "length": "0"],
        ]
        var reason: NSString?
        return SUAppcastItem(dictionary: props, relativeTo: nil, failureReason: &reason)
    }

    private let debugReleaseNotesHTML = """
        <h3>Added</h3>
        <ul>
          <li>Custom in-panel update UI — no more separate Sparkle window</li>
          <li>Copy-on-select now works in Terminal and VS Code</li>
        </ul>
        <h3>Fixed</h3>
        <ul>
          <li>Panel no longer flickers when switching between tabs rapidly</li>
          <li>Rich text paste now respects the <strong>alternate shortcut</strong> setting correctly</li>
        </ul>
        """
    #endif
}
