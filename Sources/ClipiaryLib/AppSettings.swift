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
        static let localAltPasteHotKeyKeyCode = "localAltPasteHotKeyKeyCode"
        static let localAltPasteHotKeyModifiers = "localAltPasteHotKeyModifiers"
        static let globalAltPasteHotKeyKeyCode = "globalAltPasteHotKeyKeyCode"
        static let globalAltPasteHotKeyModifiers = "globalAltPasteHotKeyModifiers"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let moveToTopOnPaste = "moveToTopOnPaste"
        static let moveToTopSkipFavorites = "moveToTopSkipFavorites"
        static let showItemDetails = "showItemDetails"
        static let alwaysShowSearch = "alwaysShowSearch"
        static let copyOnSelectBufferLimit = "copyOnSelectBufferLimit"
        static let showAppIcons = "showAppIcons"
        static let pasteCountBarScheme = "pasteCountBarScheme"
        static let itemLineLimit = "itemLineLimit"
        static let autoMonospaceFromTerminals = "autoMonospaceFromTerminals"
        static let terminalBundleIDs = "terminalBundleIDs"
        static let selectedThemeID = "selectedThemeID"
        static let showFavoriteTabBadges = "showFavoriteTabBadges"
        static let isRichTextCaptureEnabled = "isRichTextCaptureEnabled"
        static let richTextPasteDefault = "richTextPasteDefault"
    }

    static let defaultTerminalBundleIDsString = "com.apple.Terminal, com.googlecode.iterm2, com.mitchellh.ghostty, com.microsoft.VSCode, com.jetbrains.goland"

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

    var moveToTopSkipFavorites: Bool {
        didSet { defaults.set(moveToTopSkipFavorites, forKey: Keys.moveToTopSkipFavorites) }
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

    var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: Keys.selectedThemeID) }
    }

    var showFavoriteTabBadges: Bool {
        didSet { defaults.set(showFavoriteTabBadges, forKey: Keys.showFavoriteTabBadges) }
    }

    var isRichTextCaptureEnabled: Bool {
        didSet { defaults.set(isRichTextCaptureEnabled, forKey: Keys.isRichTextCaptureEnabled) }
    }

    var richTextPasteDefault: Bool {
        didSet { defaults.set(richTextPasteDefault, forKey: Keys.richTextPasteDefault) }
    }

    var localAltPasteHotKeyKeyCode: Int {
        didSet { defaults.set(localAltPasteHotKeyKeyCode, forKey: Keys.localAltPasteHotKeyKeyCode) }
    }

    var localAltPasteHotKeyModifiers: Int {
        didSet { defaults.set(localAltPasteHotKeyModifiers, forKey: Keys.localAltPasteHotKeyModifiers) }
    }

    var globalAltPasteHotKeyKeyCode: Int {
        didSet { defaults.set(globalAltPasteHotKeyKeyCode, forKey: Keys.globalAltPasteHotKeyKeyCode) }
    }

    var globalAltPasteHotKeyModifiers: Int {
        didSet { defaults.set(globalAltPasteHotKeyModifiers, forKey: Keys.globalAltPasteHotKeyModifiers) }
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
            Keys.moveToTopSkipFavorites: false,
            Keys.showItemDetails: true,
            Keys.alwaysShowSearch: true,
            Keys.copyOnSelectBufferLimit: 3,
            Keys.showAppIcons: true,
            Keys.pasteCountBarScheme: "ocean",
            Keys.itemLineLimit: 2,
            Keys.autoMonospaceFromTerminals: true,
            Keys.terminalBundleIDs: Self.defaultTerminalBundleIDsString,
            Keys.selectedThemeID: "default",
            Keys.showFavoriteTabBadges: true,
            Keys.isRichTextCaptureEnabled: true,
            Keys.richTextPasteDefault: true,
            Keys.localAltPasteHotKeyKeyCode: 36, // Return
            Keys.localAltPasteHotKeyModifiers: Int(NSEvent.ModifierFlags.shift.rawValue),
            Keys.globalAltPasteHotKeyKeyCode: 9,  // V
            Keys.globalAltPasteHotKeyModifiers: Int(NSEvent.ModifierFlags.control.union(.option).union(.command).rawValue),
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
        moveToTopSkipFavorites = defaults.bool(forKey: Keys.moveToTopSkipFavorites)
        showItemDetails = defaults.bool(forKey: Keys.showItemDetails)
        alwaysShowSearch = defaults.bool(forKey: Keys.alwaysShowSearch)
        copyOnSelectBufferLimit = defaults.integer(forKey: Keys.copyOnSelectBufferLimit)
        showAppIcons = defaults.bool(forKey: Keys.showAppIcons)
        pasteCountBarScheme = defaults.string(forKey: Keys.pasteCountBarScheme) ?? "ocean"
        itemLineLimit = defaults.integer(forKey: Keys.itemLineLimit)
        autoMonospaceFromTerminals = defaults.bool(forKey: Keys.autoMonospaceFromTerminals)
        terminalBundleIDs = defaults.string(forKey: Keys.terminalBundleIDs) ?? Self.defaultTerminalBundleIDsString
        selectedThemeID = defaults.string(forKey: Keys.selectedThemeID) ?? "default"
        showFavoriteTabBadges = defaults.bool(forKey: Keys.showFavoriteTabBadges)
        isRichTextCaptureEnabled = defaults.bool(forKey: Keys.isRichTextCaptureEnabled)
        richTextPasteDefault = defaults.bool(forKey: Keys.richTextPasteDefault)
        localAltPasteHotKeyKeyCode = defaults.integer(forKey: Keys.localAltPasteHotKeyKeyCode)
        localAltPasteHotKeyModifiers = defaults.integer(forKey: Keys.localAltPasteHotKeyModifiers)
        globalAltPasteHotKeyKeyCode = defaults.integer(forKey: Keys.globalAltPasteHotKeyKeyCode)
        globalAltPasteHotKeyModifiers = defaults.integer(forKey: Keys.globalAltPasteHotKeyModifiers)
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

    var localAltPasteShortcut: GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(localAltPasteHotKeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(localAltPasteHotKeyModifiers))
        )
    }

    func updateLocalAltPasteShortcut(_ shortcut: GlobalShortcut) {
        localAltPasteHotKeyKeyCode = Int(shortcut.keyCode)
        localAltPasteHotKeyModifiers = Int(shortcut.modifiers.rawValue)
    }

    var globalAltPasteShortcut: GlobalShortcut {
        GlobalShortcut(
            keyCode: UInt32(globalAltPasteHotKeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(globalAltPasteHotKeyModifiers))
        )
    }

    func updateGlobalAltPasteShortcut(_ shortcut: GlobalShortcut) {
        globalAltPasteHotKeyKeyCode = Int(shortcut.keyCode)
        globalAltPasteHotKeyModifiers = Int(shortcut.modifiers.rawValue)
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
