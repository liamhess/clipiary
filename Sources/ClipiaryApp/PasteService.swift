import AppKit

enum PasteService {
    static func paste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let commandFlag = CGEventFlags.maskCommand
        let vKey: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = commandFlag
        keyUp?.flags = commandFlag
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
