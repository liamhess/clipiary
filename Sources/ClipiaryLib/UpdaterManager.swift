import AppKit
import Sparkle

@MainActor @Observable
public final class UpdaterManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    private var controller: SPUStandardUpdaterController?
    var updateAvailable = false

    private override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var isConfigured: Bool {
        controller != nil
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    var isShowingUpdateWindow: Bool {
        guard controller != nil else { return false }
        return NSApp.windows.contains { $0.isVisible && type(of: $0).description().contains("Sparkle") }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    public nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            updateAvailable = true
        }
    }

    public nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        MainActor.assumeIsolated {
            updateAvailable = false
        }
    }
}
