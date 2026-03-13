import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusSyncTimer: Timer?
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        item.button?.image = NSImage(systemSymbolName: "paperclip.circle.fill", accessibilityDescription: "Clipiary")
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        return item
    }()

    private var panel: FloatingPanel<AnyView>?
    private let appState = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        appState.start()
        updateStatusItem()
        statusSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            title: "Clipiary",
            statusBarButton: statusItem.button
        ) {
            AnyView(
                PanelRootView()
                    .environment(appState)
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePanel()
        return true
    }

    @objc
    private func togglePanel() {
        panel?.toggle()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isAutoSelectEnabled
        button.appearsDisabled = isPaused

        if appState.settings.showRecentItemInStatusBar, let text = appState.history.items.first?.displayText {
            button.title = " " + text.prefix(18)
        } else {
            button.title = ""
        }
    }
}
