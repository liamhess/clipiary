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
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let moveToTopOnPaste = "moveToTopOnPaste"
        static let showItemDetails = "showItemDetails"
    }

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
            Keys.panelWidth: 376.0,
            Keys.panelHeight: 600.0,
            Keys.moveToTopOnPaste: true,
            Keys.showItemDetails: true,
        ])

        isClipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        isCopyOnSelectEnabled = defaults.bool(forKey: Keys.copyOnSelectEnabled)
        minimumSelectionLength = defaults.integer(forKey: Keys.minimumSelectionLength)
        copyOnSelectCooldownMilliseconds = defaults.integer(forKey: Keys.copyOnSelectCooldownMilliseconds)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        historyLimit = defaults.integer(forKey: Keys.historyLimit)
        globalHotKeyKeyCode = defaults.integer(forKey: Keys.globalHotKeyKeyCode)
        globalHotKeyModifiers = defaults.integer(forKey: Keys.globalHotKeyModifiers)
        panelWidth = defaults.double(forKey: Keys.panelWidth)
        panelHeight = defaults.double(forKey: Keys.panelHeight)
        moveToTopOnPaste = defaults.bool(forKey: Keys.moveToTopOnPaste)
        showItemDetails = defaults.bool(forKey: Keys.showItemDetails)
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
}
