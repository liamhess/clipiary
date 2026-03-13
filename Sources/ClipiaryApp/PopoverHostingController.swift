import AppKit
import SwiftUI

@MainActor
final class PopoverHostingController: NSHostingController<AnyView> {
    private let appState: AppState
    private let onClose: () -> Void

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        super.init(rootView: AnyView(PanelRootView().environment(appState)))
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
