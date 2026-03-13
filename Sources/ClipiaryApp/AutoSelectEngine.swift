import AppKit
import Combine
import Foundation

@MainActor
final class AutoSelectEngine {
    private let settings: AppSettings
    private let permissionManager: AccessibilityPermissionManager
    private let captureCoordinator: CaptureCoordinator
    private let appMonitor = FrontmostAppMonitor()
    private let observer = SelectionObserver()

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var fallbackRefreshTimer: Timer?
    private var scheduledRefresh: DispatchWorkItem?

    init(
        settings: AppSettings,
        permissionManager: AccessibilityPermissionManager,
        captureCoordinator: CaptureCoordinator
    ) {
        self.settings = settings
        self.permissionManager = permissionManager
        self.captureCoordinator = captureCoordinator
    }

    func start() {
        observer.onSelectionEvent = { [weak self] in
            self?.scheduleRefresh(delay: 0.1)
        }

        appMonitor.$currentApp
            .receive(on: RunLoop.main)
            .sink { [weak self] app in
                self?.handleFrontmostAppChange(app)
            }
            .store(in: &cancellables)

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.permissionManager.refreshTrust()
            }
        }

        fallbackRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(delay: 0)
            }
        }

        handleFrontmostAppChange(appMonitor.currentApp)
    }

    private func handleFrontmostAppChange(_ app: NSRunningApplication?) {
        observer.attach(to: app)
        scheduleRefresh(delay: 0.2)
    }

    private func scheduleRefresh(delay: TimeInterval) {
        scheduledRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshSelection()
        }
        scheduledRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func refreshSelection() {
        permissionManager.refreshTrust()
        guard settings.isAutoSelectEnabled, permissionManager.isTrusted else {
            return
        }

        let snapshot = SelectionReader.read(from: appMonitor.currentApp)
        captureCoordinator.consumeAutoSelectSnapshot(snapshot)
    }
}
