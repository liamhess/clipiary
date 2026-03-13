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
        static let showRecentItemInStatusBar = "showRecentItemInStatusBar"
        static let pasteOnSelect = "pasteOnSelect"
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

    var showRecentItemInStatusBar: Bool {
        didSet { defaults.set(showRecentItemInStatusBar, forKey: Keys.showRecentItemInStatusBar) }
    }

    var pasteOnSelect: Bool {
        didSet { defaults.set(pasteOnSelect, forKey: Keys.pasteOnSelect) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.clipboardMonitoringEnabled: true,
            Keys.autoSelectEnabled: false,
            Keys.minimumSelectionLength: 2,
            Keys.autoSelectCooldownMilliseconds: 350,
            Keys.ignoredBundleIDs: [],
            Keys.historyLimit: 100,
            Keys.showRecentItemInStatusBar: false,
            Keys.pasteOnSelect: false,
        ])

        isClipboardMonitoringEnabled = defaults.bool(forKey: Keys.clipboardMonitoringEnabled)
        isAutoSelectEnabled = defaults.bool(forKey: Keys.autoSelectEnabled)
        minimumSelectionLength = defaults.integer(forKey: Keys.minimumSelectionLength)
        autoSelectCooldownMilliseconds = defaults.integer(forKey: Keys.autoSelectCooldownMilliseconds)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        historyLimit = defaults.integer(forKey: Keys.historyLimit)
        showRecentItemInStatusBar = defaults.bool(forKey: Keys.showRecentItemInStatusBar)
        pasteOnSelect = defaults.bool(forKey: Keys.pasteOnSelect)
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
