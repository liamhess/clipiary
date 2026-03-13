import AppKit
import SwiftUI

struct PopoverSearchField: NSViewRepresentable {
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> ClipiarySearchField {
        let searchField = ClipiarySearchField(frame: .zero)
        searchField.delegate = context.coordinator
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.placeholderString = "Search clipboard history"
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.submitSearch(_:))
        searchField.commandHandler = context.coordinator
        return searchField
    }

    func updateNSView(_ searchField: ClipiarySearchField, context: Context) {
        context.coordinator.appState = appState
        searchField.commandHandler = context.coordinator

        if searchField.stringValue != appState.searchQuery {
            searchField.stringValue = appState.searchQuery
        }

        if context.coordinator.lastFocusRequestID != appState.searchFocusRequestID {
            context.coordinator.lastFocusRequestID = appState.searchFocusRequestID
            DispatchQueue.main.async {
                searchField.window?.makeFirstResponder(searchField)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate, NSControlTextEditingDelegate, ClipiarySearchFieldCommandHandler {
        var appState: AppState
        var lastFocusRequestID = 0

        init(appState: AppState) {
            self.appState = appState
        }

        @objc
        func submitSearch(_ sender: NSSearchField) {
            appState.searchQuery = sender.stringValue
            appState.ensureSelection()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            appState.searchQuery = searchField.stringValue
            appState.ensureSelection()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                appState.moveSelection(direction: -1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                appState.moveSelection(direction: 1)
                return true
            case #selector(NSResponder.moveLeft(_:)):
                appState.moveTab(direction: -1)
                return true
            case #selector(NSResponder.moveRight(_:)):
                appState.moveTab(direction: 1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                appState.restoreSelectedItem()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                appState.deleteSelectedItem()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                NSApp.sendAction(#selector(AppDelegate.closePopoverCommandFromResponderChain), to: nil, from: control)
                return true
            default:
                return false
            }
        }

        func toggleFavoriteFromSearchField() {
            appState.toggleFavoriteSelectedItem()
        }
    }
}

@MainActor
protocol ClipiarySearchFieldCommandHandler: AnyObject {
    func toggleFavoriteFromSearchField()
}

final class ClipiarySearchField: NSSearchField {
    weak var commandHandler: ClipiarySearchFieldCommandHandler?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let normalizedCharacters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command, .shift], normalizedCharacters == "f" {
            commandHandler?.toggleFavoriteFromSearchField()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
