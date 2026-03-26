import AppKit
import SwiftUI

@MainActor
final class FloatingPanel: NSPanel {
    private let statusBarButton: NSStatusBarButton?
    private let appState: AppState
    private var isSuppressingPersistence = false
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
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Clipiary"
        isRestorable = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        minSize = NSSize(width: 300, height: 400)
        maxSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)

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
        let preferredSize = NSSize(width: settings.panelWidth, height: settings.panelHeight)

        guard let screen = NSScreen.main else {
            setContentSize(preferredSize)
            orderFrontRegardless()
            makeKey()
            return
        }

        let targetOrigin: NSPoint
        var size = preferredSize
        if let statusBarButton,
           let window = statusBarButton.window {
            let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
            let screenRect = window.convertToScreen(rectInWindow)
            let maxHeight = screenRect.minY - screen.visibleFrame.minY
            size.width = min(size.width, screen.visibleFrame.width)
            size.height = min(size.height, maxHeight)
            targetOrigin = NSPoint(
                x: min(screenRect.minX, screen.visibleFrame.maxX - size.width),
                y: screenRect.minY - size.height
            )
        } else {
            size.width = min(size.width, screen.visibleFrame.width)
            size.height = min(size.height, screen.visibleFrame.height)
            targetOrigin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }

        isSuppressingPersistence = true
        setFrame(NSRect(origin: targetOrigin, size: size), display: true)
        isSuppressingPersistence = false
        orderFrontRegardless()
        makeKey()
        statusBarButton?.isHighlighted = true
    }

    override func resignKey() {
        super.resignKey()
        // Don't close if the settings window is taking focus.
        if SettingsWindowController.shared.isVisible {
            return
        }
        // Don't close if the Sparkle updater is showing a window.
        if UpdaterManager.shared.isShowingUpdateWindow {
            return
        }
        // Don't close if the mouse is near the panel frame —
        // the user is resizing or dragging, not clicking away.
        // Inset by -6 to cover corner resize handles that sit at the frame edge.
        let mouseLocation = NSEvent.mouseLocation
        if frame.insetBy(dx: -6, dy: -6).contains(mouseLocation) {
            return
        }
        close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, appState.showingFavoriteTabPicker, !appState.isRecordingItemShortcut, !appState.isEditingSnippetDescription {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.isDisjoint(with: [.command, .option, .control]) {
                switch event.keyCode {
                case 125: // Down
                    appState.movePickerSelection(direction: 1)
                case 126: // Up
                    appState.movePickerSelection(direction: -1)
                case 36, 49: // Return, Space
                    appState.confirmPickerSelection()
                case 46: // M
                    appState.togglePickerMonospace()
                case 1: // S
                    appState.startRecordingItemShortcut()
                case 2: // D
                    appState.isEditingSnippetDescription = true
                case 51: // Delete/Backspace
                    appState.removeItemShortcut()
                case 53: // Escape
                    close()
                default:
                    break
                }
                return
            }
        }
        // Cmd+, opens settings — intercept before super to prevent beep
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 43 {
            SettingsWindowController.shared.open()
            return
        }
        // Escape: close preview first, then close panel
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control]) {
            if appState.isPreviewVisible {
                appState.isPreviewVisible = false
                return
            }
            close()
            return
        }
        super.sendEvent(event)
    }

    override func close() {
        if appState.showingFavoriteTabPicker {
            appState.showingFavoriteTabPicker = false
            appState.isRecordingItemShortcut = false
            appState.isEditingSnippetDescription = false
            appState.itemShortcutError = nil
            appState.requestSearchFocus()
            return
        }
        SettingsWindowController.shared.close()
        super.close()
        statusBarButton?.isHighlighted = false
        onClose?()
    }

    override var canBecomeKey: Bool {
        true
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard !isSuppressingPersistence else { return }
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
        sizingOptions = []
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

        // Cmd+Down or Opt+Down — jump to last item
        if !modifiers.isDisjoint(with: [.command, .option]), event.keyCode == 125 {
            appState.moveToLast()
            return true
        }

        // Cmd+Up or Opt+Up — jump to first item
        if !modifiers.isDisjoint(with: [.command, .option]), event.keyCode == 126 {
            appState.moveToFirst()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }
}
