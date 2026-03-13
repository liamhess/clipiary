import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SelectionObserver {
    var onSelectionEvent: (() -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var focusedElement: AXUIElement?
    private var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    func attach(to app: NSRunningApplication?) {
        tearDown()

        guard let app else {
            return
        }

        var createdObserver: AXObserver?
        let error = AXObserverCreate(app.processIdentifier, Self.callback, &createdObserver)
        guard error == .success, let createdObserver else {
            return
        }

        observer = createdObserver
        appElement = AXUIElementCreateApplication(app.processIdentifier)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .defaultMode)

        guard let appElement else {
            return
        }

        register(kAXFocusedWindowChangedNotification as String, on: appElement)
        register(kAXFocusedUIElementChangedNotification as String, on: appElement)
        register(kAXSelectedTextChangedNotification as String, on: appElement)
        register(kAXValueChangedNotification as String, on: appElement)
        refreshFocusedElementObservation()
    }

    private func handle(notification: String) {
        if notification == (kAXFocusedUIElementChangedNotification as String) ||
            notification == (kAXFocusedWindowChangedNotification as String) {
            refreshFocusedElementObservation()
        }

        onSelectionEvent?()
    }

    private func refreshFocusedElementObservation() {
        if let focusedElement {
            unregister(kAXSelectedTextChangedNotification as String, from: focusedElement)
            unregister(kAXValueChangedNotification as String, from: focusedElement)
        }

        focusedElement = SelectionReader.focusedElement(in: appElement)
        if let focusedElement {
            register(kAXSelectedTextChangedNotification as String, on: focusedElement)
            register(kAXValueChangedNotification as String, on: focusedElement)
        }
    }

    private func register(_ notification: String, on element: AXUIElement) {
        guard let observer else {
            return
        }

        let error = AXObserverAddNotification(observer, element, notification as CFString, refcon)
        if error == .notificationAlreadyRegistered || error == .notificationUnsupported {
            return
        }
    }

    private func unregister(_ notification: String, from element: AXUIElement) {
        guard let observer else {
            return
        }

        AXObserverRemoveNotification(observer, element, notification as CFString)
    }

    private func tearDown() {
        if let observer {
            if let focusedElement {
                unregister(kAXSelectedTextChangedNotification as String, from: focusedElement)
                unregister(kAXValueChangedNotification as String, from: focusedElement)
            }

            if let appElement {
                unregister(kAXFocusedWindowChangedNotification as String, from: appElement)
                unregister(kAXFocusedUIElementChangedNotification as String, from: appElement)
                unregister(kAXSelectedTextChangedNotification as String, from: appElement)
                unregister(kAXValueChangedNotification as String, from: appElement)
            }

            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observer = nil
        appElement = nil
        focusedElement = nil
    }

    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else {
            return
        }

        let instance = Unmanaged<SelectionObserver>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        Task { @MainActor in
            instance.handle(notification: name)
        }
    }
}
