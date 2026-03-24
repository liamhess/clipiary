import AppKit
import Carbon.HIToolbox

struct GlobalShortcut: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else {
            return nil
        }

        let ignoredKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !ignoredKeyCodes.contains(event.keyCode) else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    var displayString: String {
        let modifierString = [
            modifiers.contains(.control) ? "^" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : "",
        ].joined()

        return modifierString + keyDisplayName
    }

    private var keyDisplayName: String {
        GlobalShortcut.keyNames[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]
}
