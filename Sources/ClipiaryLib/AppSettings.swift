import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let clipboardMonitoringEnabled = "clipboardMonitoringEnabled"
        static let copyOnSelectEnabled = "copyOnSelectEnabled"
        static let minimumSelectionLength = "minimumSelectionLength"
        static let copyOnSelectCooldownMilliseconds = "copyOnSelectCooldownMilliseconds"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let historyLimit = "historyLimit"
        static let globalHotKeyKeyCode = "globalHotKeyKeyCode"
        static let globalHotKeyModifiers = "globalHotKeyModifiers"
        static let quickPasteHotKeyKeyCode = "quickPasteHotKeyKeyCode"
        static let quickPasteHotKeyModifiers = "quickPasteHotKeyModifiers"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let moveToTopOnPaste = "moveToTopOnPaste"
        static let showItemDetails = "showItemDetails"
        static let alwaysShowSearch = "alwaysShowSearch"
        static let copyOnSelectBufferLimit = "copyOnSelectBufferLimit"
        static let showAppIcons = "showAppIcons"
        static let pasteCountBarScheme = "pasteCountBarScheme"
        static let itemLineLimit = "itemLineLimit"
        static let autoMonospaceFromTerminals = "autoMonospaceFromTerminals"
        static let terminalBundleIDs = "terminalBundleIDs"
    }

    static let defaultTerminalBundleIDsString = "com.apple.Terminal, com.googlecode.iterm2, com.mitchellh.ghostty"

    private let defaults: UserDefaults

    var isClipboardMonitoringEnabled: Bool {
        didSet { defaults.set(isClipboardMonitoringEnabled, forKey: Keys.clipboardMonitoringEnabled) }
    }

    var isCopyOnSelectEnabled: Bool {
        didSet { defaults.set(isCopyOnSelectEnabled, forKey: Keys.copyOnSelectEnabled) }
    }

    var minimumSelectionLength: Int {
        didSet { defaults.set(minimumSelectionLength, forKey: Keys.minimumSelectionLength) }
    }

    var copyOnSelectCooldownMilliseconds: Int {
        didSet { defaults.set(copyOnSelectCooldownMilliseconds, forKey: Keys.copyOnSelectCooldownMilliseconds) }
    }

    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    var globalHotKeyKeyCode: Int {
        didSet { defaults.set(globalHotKeyKeyCode, forKey: Keys.globalHotKeyKeyCode) }
    }

    var globalHotKeyModifiers: Int {
        didSet { defaults.set(globalHotKeyModifiers, forKey: Keys.globalHotKeyModifiers) }
    }

    var quickPasteHotKeyKeyCode: Int {
        didSet { defaults.set(quickPasteHotKeyKeyCode, forKey: Keys.quickPasteHotKeyKeyCode) }
    }

    var quickPasteHotKeyModifiers: Int {
        didSet { defaults.set(quickPasteHotKeyModifiers, forKey: Keys.quickPasteHotKeyModifiers) }
    }

    var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) }
    }

    var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Keys.panelHeight) }
    }

    var moveToTopOnPaste: Bool {
        didSet { defaults.set(moveToTopOnPaste, forKey: Keys.moveToTopOnPaste) }
    }

    var showItemDetails: Bool {
        didSet { defaults.set(showItemDetails, forKey: Keys.showItemDetails) }
    }

    var alwaysShowSearch: Bool {
        didSet { defaults.set(alwaysShowSearch, forKey: Keys.alwaysShowSearch) }
    }

    var copyOnSelectBufferLimit: Int {
        didSet { defaults.set(copyOnSelectBufferLimit, forKey: Keys.copyOnSelectBufferLimit) }
    }

    var showAppIcons: Bool {
        didSet { defaults.set(showAppIcons, forKey: Keys.showAppIcons) }
    }

    var pasteCountBarScheme: String {
        didSet { defaults.set(pasteCountBarScheme, forKey: Keys.pasteCountBarScheme) }
    }

    var itemLineLimit: Int {
        didSet { defaults.set(itemLineLimit, forKey: Keys.itemLineLimit) }
    }

    var autoMonospaceFromTerminals: Bool {
        didSet { defaults.set(autoMonospaceFromTerminals, forKey: Keys.autoMonospaceFromTerminals) }
    }

    var terminalBundleIDs: String {
        didSet { defaults.set(terminalBundleIDs, forKey: Keys.terminalBundleIDs) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.clipboardMonitoringEnabled: true,
            Keys.copyOnSelectEnabled: false,
            Keys.minimumSelectionLength: 2,
            Keys.copyOnSelectCooldownMilliseconds: 350,
            Keys.ignoredBundleIDs: [],
            Keys.historyLimit: 1_000,
            Keys.globalHotKeyKeyCode: 9,
            Keys.globalHotKeyModifiers: Int((NSEvent.ModifierFlags.command.union(.shift)).rawValue),
            Keys.quickPasteHotKeyKeyCode: 35,
            Keys.quickPasteHotKeyModifiers: Int((NSEvent.ModifierFlags.control.union(.option).union(.command)).rawValue),
            Keys.panelWidth: 376.0,
            Keys.panelHeight: 600.0,
            Keys.moveToTopOnPaste: true,
            Keys.showItemDetails: true,
            Keys.alwaysShowSearch: true,
            Keys.copyOnSelectBufferLimit: 3,
            Keys.showAppIcons: true,
            Keys.pasteCountBarScheme: "ocean",
            Keys.itemLineLimit: 2,
            Keys.autoMonospaceFromTerminals: true,
            Keys.terminalBundleIDs: Self.defaultTerminalBundleIDsString,
        ])

        isClipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        isCopyOnSelectEnabled = defaults.bool(forKey: Keys.copyOnSelectEnabled)
        minimumSelectionLength = defaults.integer(forKey: Keys.minimumSelectionLength)
        copyOnSelectCooldownMilliseconds = defaults.integer(forKey: Keys.copyOnSelectCooldownMilliseconds)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        historyLimit = defaults.integer(forKey: Keys.historyLimit)
        globalHotKeyKeyCode = defaults.integer(forKey: Keys.globalHotKeyKeyCode)
        globalHotKeyModifiers = defaults.integer(forKey: Keys.globalHotKeyModifiers)
        quickPasteHotKeyKeyCode = defaults.integer(forKey: Keys.quickPasteHotKeyKeyCode)
        quickPasteHotKeyModifiers = defaults.integer(forKey: Keys.quickPasteHotKeyModifiers)
        panelWidth = defaults.double(forKey: Keys.panelWidth)
        panelHeight = defaults.double(forKey: Keys.panelHeight)
        moveToTopOnPaste = defaults.bool(forKey: Keys.moveToTopOnPaste)
        showItemDetails = defaults.bool(forKey: Keys.showItemDetails)
        alwaysShowSearch = defaults.bool(forKey: Keys.alwaysShowSearch)
        copyOnSelectBufferLimit = defaults.integer(forKey: Keys.copyOnSelectBufferLimit)
        showAppIcons = defaults.bool(forKey: Keys.showAppIcons)
        pasteCountBarScheme = defaults.string(forKey: Keys.pasteCountBarScheme) ?? "ocean"
        itemLineLimit = defaults.integer(forKey: Keys.itemLineLimit)
        autoMonospaceFromTerminals = defaults.bool(forKey: Keys.autoMonospaceFromTerminals)
        terminalBundleIDs = defaults.string(forKey: Keys.terminalBundleIDs) ?? Self.defaultTerminalBundleIDsString
    }

    var globalShortcut: GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(globalHotKeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(globalHotKeyModifiers))
        )
    }

    func updateGlobalShortcut(_ shortcut: GlobalShortcut) {
        globalHotKeyKeyCode = Int(shortcut.keyCode)
        globalHotKeyModifiers = Int(shortcut.modifiers.rawValue)
    }

    var quickPasteShortcut: GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(quickPasteHotKeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(quickPasteHotKeyModifiers))
        )
    }

    func updateQuickPasteShortcut(_ shortcut: GlobalShortcut) {
        quickPasteHotKeyKeyCode = Int(shortcut.keyCode)
        quickPasteHotKeyModifiers = Int(shortcut.modifiers.rawValue)
    }

    func ignores(bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }

        return ignoredBundleIDs.contains(bundleID)
    }

    func toggleIgnored(bundleID: String) {
        if ignoredBundleIDs.contains(bundleID) {
            ignoredBundleIDs.removeAll { $0 == bundleID }
        } else {
            ignoredBundleIDs.append(bundleID)
            ignoredBundleIDs.sort()
        }
    }

    func isTerminalApp(bundleID: String?) -> Bool {
        guard autoMonospaceFromTerminals, let bundleID else { return false }
        return terminalBundleIDs
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces) == bundleID }
    }
}
