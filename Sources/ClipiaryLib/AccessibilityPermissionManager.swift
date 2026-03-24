import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class AccessibilityPermissionManager {
    private(set) var isTrusted = AXIsProcessTrusted()

    func refreshTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestAccessPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
