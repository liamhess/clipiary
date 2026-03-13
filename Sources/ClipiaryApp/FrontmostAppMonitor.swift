import AppKit
import Combine

@MainActor
final class FrontmostAppMonitor: ObservableObject {
    @Published private(set) var currentApp: NSRunningApplication?

    private var activationObserver: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        currentApp = workspace.frontmostApplication
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.currentApp = app
            }
        }
    }
}
