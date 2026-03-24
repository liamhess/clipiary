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

        let manualError = AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        let enhancedError = AXUIElementSetAttributeValue(
            appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
        )

        if manualError == .success || enhancedError == .success {
            return .enabled
        }

        let primaryError = manualError
        switch primaryError {
        case .attributeUnsupported, .noValue, .cannotComplete:
            return .unsupported
        default:
            return .failed(primaryError)
        }
    }
}
