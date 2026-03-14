import AppKit
import ApplicationServices
import Foundation

enum SelectionReader {
    static func read(from app: NSRunningApplication?) -> SelectionSnapshot {
        guard let app else {
            return SelectionSnapshot(
                appName: "No App",
                bundleID: nil,
                role: nil,
                subrole: nil,
                selectedText: nil,
                selectionReadable: false,
                failureReason: "No frontmost app"
            )
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = focusedElement(in: appElement) else {
            return SelectionSnapshot(
                appName: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier,
                role: nil,
                subrole: nil,
                selectedText: nil,
                selectionReadable: false,
                failureReason: "Focused element unavailable"
            )
        }

        let primaryAttributes = elementAttributes(for: focusedElement)
        if isSecureField(role: primaryAttributes.role, subrole: primaryAttributes.subrole) {
            return SelectionSnapshot(
                appName: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier,
                role: primaryAttributes.role,
                subrole: primaryAttributes.subrole,
                selectedText: nil,
                selectionReadable: false,
                failureReason: "Secure text field"
            )
        }

        let candidates = selectionCandidates(primary: focusedElement, appElement: appElement)
        for candidate in candidates {
            let attributes = elementAttributes(for: candidate)
            if isSecureField(role: attributes.role, subrole: attributes.subrole) {
                continue
            }

            if let selectedText = selectedText(from: candidate) {
                return SelectionSnapshot(
                    appName: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier,
                    role: attributes.role,
                    subrole: attributes.subrole,
                    selectedText: selectedText,
                    selectionReadable: true,
                    failureReason: selectedText.isEmpty ? "Selection empty" : nil
                )
            }
        }

        return SelectionSnapshot(
            appName: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier,
            role: primaryAttributes.role,
            subrole: primaryAttributes.subrole,
            selectedText: nil,
            selectionReadable: false,
            failureReason: failureReason(for: app.bundleIdentifier)
        )
    }

    static func focusedElement(in appElement: AXUIElement?) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        let focusedSystem: AXUIElement? = attribute(kAXFocusedUIElementAttribute as String, on: systemWide)
        if let focusedSystem {
            return focusedSystem
        }

        if let appElement,
           let focusedInApp: AXUIElement = attribute(kAXFocusedUIElementAttribute as String, on: appElement) {
            return focusedInApp
        }

        return nil
    }

    private static func attribute<T>(_ name: String, on element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value else {
            return nil
        }

        return value as? T
    }

    private static func parameterizedAttribute<T>(_ name: String, on element: AXUIElement, parameter: CFTypeRef) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value)
        guard error == .success, let value else {
            return nil
        }

        return value as? T
    }

    private static func stringAttribute(_ name: String, on element: AXUIElement) -> String? {
        if let value: String = attribute(name, on: element) {
            return value
        }

        if let attributedValue: NSAttributedString = attribute(name, on: element) {
            return attributedValue.string
        }

        return nil
    }

    private static func rangeAttribute(_ name: String, on element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(name, on: element), AXValueGetType(value) == .cfRange else {
            return nil
        }

        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private static func textMarkerRangeAttribute(_ name: String, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }

        return value
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        if let selectedText = stringAttribute(kAXSelectedTextAttribute as String, on: element) {
            return selectedText
        }

        if let markerRange = textMarkerRangeAttribute(kAXSelectedTextMarkerRangeAttribute as String, on: element) {
            if let selectedText: String = parameterizedAttribute(
                kAXStringForTextMarkerRangeParameterizedAttribute as String,
                on: element,
                parameter: markerRange
            ) {
                return selectedText
            }

            if let attributed: NSAttributedString = parameterizedAttribute(
                kAXAttributedStringForTextMarkerRangeParameterizedAttribute as String,
                on: element,
                parameter: markerRange
            ) {
                return attributed.string
            }
        }

        if let selectedRange = rangeAttribute(kAXSelectedTextRangeAttribute as String, on: element) {
            var mutableRange = selectedRange
            if let selectedText: String = parameterizedAttribute(
                kAXStringForRangeParameterizedAttribute as String,
                on: element,
                parameter: AXValueCreate(.cfRange, &mutableRange)!
            ) {
                return selectedText
            }

            if let value = stringAttribute(kAXValueAttribute as String, on: element) {
                return substring(in: value, range: selectedRange)
            }
        }

        return nil
    }

    private static func selectionCandidates(primary focusedElement: AXUIElement, appElement: AXUIElement) -> [AXUIElement] {
        let possible: [AXUIElement?] = [
            focusedElement,
            attribute(kAXActiveElementAttribute as String, on: focusedElement),
            attribute(kAXEditableAncestorAttribute as String, on: focusedElement),
            attribute(kAXHighestEditableAncestorAttribute as String, on: focusedElement),
            attribute(kAXActiveElementAttribute as String, on: appElement),
        ]

        var seen = Set<String>()
        var result: [AXUIElement] = []
        for element in possible {
            guard let element else {
                continue
            }

            let key = "\(Unmanaged.passUnretained(element).toOpaque())"
            guard seen.insert(key).inserted else {
                continue
            }

            result.append(element)
        }

        return result
    }

    private static func elementAttributes(for element: AXUIElement) -> (role: String?, subrole: String?) {
        (
            stringAttribute(kAXRoleAttribute as String, on: element),
            stringAttribute(kAXSubroleAttribute as String, on: element)
        )
    }

    private static func substring(in source: String, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else {
            return nil
        }

        let nsSource = source as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard NSMaxRange(nsRange) <= nsSource.length else {
            return nil
        }

        return nsSource.substring(with: nsRange)
    }

    private static func isSecureField(role: String?, subrole: String?) -> Bool {
        role == (kAXSecureTextFieldSubrole as String) || subrole == (kAXSecureTextFieldSubrole as String)
    }

    private static func failureReason(for bundleID: String?) -> String {
        guard let bundleID else {
            return "Selected text unavailable"
        }

        if [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.chromium.Chromium",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.microsoft.VSCode",
            "com.microsoft.VSCode.Insiders",
        ].contains(bundleID) {
            return "Selected text unavailable; browser accessibility may need to be enabled"
        }

        return "Selected text unavailable"
    }
}
