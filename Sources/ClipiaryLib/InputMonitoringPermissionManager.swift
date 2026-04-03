import ApplicationServices
import Observation

@MainActor
@Observable
final class InputMonitoringPermissionManager {
    private(set) var isTrusted = CGPreflightListenEventAccess()

    func refreshTrust() {
        isTrusted = CGPreflightListenEventAccess()
    }

    func requestAccessPrompt() {
        isTrusted = CGRequestListenEventAccess()
    }
}
