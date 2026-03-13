import AppKit
import ApplicationServices

enum ManualAccessibilityActivationResult {
    case enabled
    case unsupported
    case failed(AXError)
}

enum ThirdPartyAccessibilityActivator {
    static func enableIfSupported(for app: NSRunningApplication?) -> ManualAccessibilityActivationResult {
        guard let app else {
            return .unsupported
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
        let error = AXUIElementSetAttributeValue(appElement, manualAccessibilityAttribute, kCFBooleanTrue)

        switch error {
        case .success:
            return .enabled
        case .attributeUnsupported, .noValue, .cannotComplete:
            return .unsupported
        default:
            return .failed(error)
        }
    }
}
