import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusSyncTimer: Timer?
    private let popover = NSPopover()
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .removalAllowed
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipiary")
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        return item
    }()

    private let appState = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        appState.start()
        configurePopover()
        updateStatusItem()
        statusSyncTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
        return true
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let isPaused = !appState.settings.isClipboardMonitoringEnabled && !appState.settings.isAutoSelectEnabled
        button.appearsDisabled = isPaused
        button.title = ""
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: PanelRootView()
                .environment(appState)
        )
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            button.isHighlighted = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.isHighlighted = false
    }
}
