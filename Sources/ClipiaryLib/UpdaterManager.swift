import AppKit
import Sparkle

@MainActor
public final class UpdaterManager {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController?

    private init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
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
}
