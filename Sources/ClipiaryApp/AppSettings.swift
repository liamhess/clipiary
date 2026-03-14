import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let clipboardMonitoringEnabled = "clipboardMonitoringEnabled"
        static let autoSelectEnabled = "autoSelectEnabled"
        static let minimumSelectionLength = "minimumSelectionLength"
        static let autoSelectCooldownMilliseconds = "autoSelectCooldownMilliseconds"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let historyLimit = "historyLimit"
        static let globalHotKeyKeyCode = "globalHotKeyKeyCode"
        static let globalHotKeyModifiers = "globalHotKeyModifiers"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
    }

    private let defaults: UserDefaults

    var isClipboardMonitoringEnabled: Bool {
        didSet { defaults.set(isClipboardMonitoringEnabled, forKey: Keys.clipboardMonitoringEnabled) }
    }

    var isAutoSelectEnabled: Bool {
        didSet { defaults.set(isAutoSelectEnabled, forKey: Keys.autoSelectEnabled) }
    }

    var minimumSelectionLength: Int {
        didSet { defaults.set(minimumSelectionLength, forKey: Keys.minimumSelectionLength) }
    }

    var autoSelectCooldownMilliseconds: Int {
        didSet { defaults.set(autoSelectCooldownMilliseconds, forKey: Keys.autoSelectCooldownMilliseconds) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.clipboardMonitoringEnabled: true,
            Keys.autoSelectEnabled: false,
            Keys.minimumSelectionLength: 2,
            Keys.autoSelectCooldownMilliseconds: 350,
            Keys.ignoredBundleIDs: [],
            Keys.historyLimit: 150,
            Keys.globalHotKeyKeyCode: 9,
            Keys.globalHotKeyModifiers: Int((NSEvent.ModifierFlags.command.union(.shift)).rawValue),
            Keys.panelWidth: 376.0,
            Keys.panelHeight: 600.0,
        ])

        isClipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        isAutoSelectEnabled = defaults.bool(forKey: Keys.autoSelectEnabled)
        minimumSelectionLength = defaults.integer(forKey: Keys.minimumSelectionLength)
        autoSelectCooldownMilliseconds = defaults.integer(forKey: Keys.autoSelectCooldownMilliseconds)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        historyLimit = defaults.integer(forKey: Keys.historyLimit)
        globalHotKeyKeyCode = defaults.integer(forKey: Keys.globalHotKeyKeyCode)
        globalHotKeyModifiers = defaults.integer(forKey: Keys.globalHotKeyModifiers)
        panelWidth = defaults.double(forKey: Keys.panelWidth)
        panelHeight = defaults.double(forKey: Keys.panelHeight)
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
