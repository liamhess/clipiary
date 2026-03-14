import AppKit
import SwiftUI

@MainActor
final class FloatingPanel: NSPanel {
    private let statusBarButton: NSStatusBarButton?
    private let appState: AppState
    var onClose: (() -> Void)?

    init(
        statusBarButton: NSStatusBarButton?,
        appState: AppState
    ) {
        self.statusBarButton = statusBarButton
        self.appState = appState

        let settings = appState.settings
        let contentRect = NSRect(x: 0, y: 0, width: settings.panelWidth, height: settings.panelHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Clipiary"
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        minSize = NSSize(width: 300, height: 400)
        maxSize = NSSize(width: 800, height: 1200)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let hostingView = PanelHostingView(
            rootView: AnyView(PanelRootView().environment(appState)),
            appState: appState,
            onClose: { [weak self] in self?.close() }
        )
        contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: self
        )
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        let settings = appState.settings
        let size = NSSize(width: settings.panelWidth, height: settings.panelHeight)

        guard let screen = NSScreen.main else {
            setContentSize(size)
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
                x: min(screenRect.minX, screen.visibleFrame.maxX - size.width),
                y: screenRect.minY - size.height
            )
        } else {
            targetOrigin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }

        setFrame(NSRect(origin: targetOrigin, size: size), display: true)
        orderFrontRegardless()
        makeKey()
        statusBarButton?.isHighlighted = true
    }

    override func resignKey() {
        super.resignKey()
        // Don't close if the mouse is near the panel frame —
        // the user is resizing or dragging, not clicking away.
        // Inset by -6 to cover corner resize handles that sit at the frame edge.
        let mouseLocation = NSEvent.mouseLocation
        if frame.insetBy(dx: -6, dy: -6).contains(mouseLocation) {
            return
        }
        close()
    }

    override func close() {
        super.close()
        statusBarButton?.isHighlighted = false
        onClose?()
    }

    override var canBecomeKey: Bool {
        true
    }

    @objc private func windowDidResize(_ notification: Notification) {
        let settings = appState.settings
        settings.panelWidth = frame.width
        settings.panelHeight = frame.height
    }
}

@MainActor
private final class PanelHostingView: NSHostingView<AnyView> {
    private let appState: AppState
    private let onClose: () -> Void

    init(rootView: AnyView, appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let normalizedCharacters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command, normalizedCharacters == "f" {
            appState.requestSearchFocus()
            return true
        }

        if modifiers == .command, normalizedCharacters == "d" {
            appState.toggleFavoriteSelectedItem()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }
}
