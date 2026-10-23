import SwiftUI

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct PerfTabNameKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// Tab a row is rendered in; only used to label `[PERF]` output.
    var perfTabName: String {
        get { self[PerfTabNameKey.self] }
        set { self[PerfTabNameKey.self] = newValue }
    }
}
