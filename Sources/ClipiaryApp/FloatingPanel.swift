import AppKit
import SwiftUI

final class FloatingPanel<Content: View>: NSPanel {
    private let statusBarButton: NSStatusBarButton?

    init(
        contentRect: NSRect,
        title: String,
        statusBarButton: NSStatusBarButton?,
        @ViewBuilder content: () -> Content
    ) {
        self.statusBarButton = statusBarButton
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = title
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = NSHostingView(rootView: content().ignoresSafeArea())
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        guard let screen = NSScreen.main else {
            orderFrontRegardless()
            makeKey()
            return
        }

        let targetOrigin: NSPoint
        if let statusBarButton,
           let window = statusBarButton.window {
            let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
            let screenRect = window.convertToScreen(rectInWindow)
            targetOrigin = NSPoint(
                x: min(screenRect.minX, screen.visibleFrame.maxX - frame.width),
                y: screenRect.minY - frame.height
            )
        } else {
            targetOrigin = NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.midY - frame.height / 2
            )
        }

        setFrameOrigin(targetOrigin)
        orderFrontRegardless()
        makeKey()
        statusBarButton?.isHighlighted = true
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        super.close()
        statusBarButton?.isHighlighted = false
    }

    override var canBecomeKey: Bool {
        true
    }
}
