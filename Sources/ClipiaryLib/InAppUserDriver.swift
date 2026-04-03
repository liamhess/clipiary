import AppKit
import Sparkle

/// Routes Sparkle update callbacks into UpdaterManager's @Observable state.
/// All SPUUserDriver methods are guaranteed by Sparkle to be called on the main thread.
/// The protocol is NS_SWIFT_UI_ACTOR; conformance methods are nonisolated in Swift 6.
/// MainActor.assumeIsolated bridges safely since Sparkle guarantees main-thread delivery.
final class InAppUserDriver: NSObject, SPUUserDriver {
    var onPhaseChange: (@MainActor @Sendable (UpdatePhase) -> Void)?
    var onReleaseNotes: (@MainActor @Sendable (String?) -> Void)?
    var onDownloadExpected: (@MainActor @Sendable (Int64) -> Void)?
    var onDownloadReceived: (@MainActor @Sendable (Int64) -> Void)?
    var onExtractionProgress: (@MainActor @Sendable (Double) -> Void)?
    var onDismiss: (@MainActor @Sendable () -> Void)?

    // MARK: - Permission

    nonisolated func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void
    ) {
        MainActor.assumeIsolated {
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
        }
    }

    // MARK: - Manual Check

    nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping @Sendable () -> Void) {
        MainActor.assumeIsolated {
            onPhaseChange?(.checking(cancel: cancellation))
        }
    }

    // MARK: - Update Found

    nonisolated func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        MainActor.assumeIsolated {
            onPhaseChange?(.updateFound(item: appcastItem, state: state, reply: reply))            // Seed embedded release notes immediately (no separate download needed).
            // showUpdateReleaseNotes(with:) is only called for external releaseNotesLink.
            if let description = appcastItem.itemDescription {
                let html: String
                if appcastItem.itemDescriptionFormat == "markdown" {
                    html = markdownToHTML(description)
                } else {
                    html = description
                }
                onReleaseNotes?(html)
            }
        }
    }

    nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        MainActor.assumeIsolated {
            let encoding: String.Encoding = {
                guard let name = downloadData.textEncodingName else { return .utf8 }
                let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
                guard cfEncoding != kCFStringEncodingInvalidId else { return .utf8 }
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            }()
            onReleaseNotes?(String(data: downloadData.data, encoding: encoding))
        }
    }

    nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        MainActor.assumeIsolated {
            onReleaseNotes?(nil)
        }
    }

    // MARK: - No Update / Error

    nonisolated func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping @Sendable () -> Void
    ) {
        MainActor.assumeIsolated {
            onPhaseChange?(.notFound(acknowledge: acknowledgement))
        }
    }

    nonisolated func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping @Sendable () -> Void
    ) {
        MainActor.assumeIsolated {
            onPhaseChange?(.error(message: error.localizedDescription, acknowledge: acknowledgement))
        }
    }

    // MARK: - Download

    nonisolated func showDownloadInitiated(cancellation: @escaping @Sendable () -> Void) {
        MainActor.assumeIsolated {
            onPhaseChange?(.downloading(cancel: cancellation))
        }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        MainActor.assumeIsolated {
            onDownloadExpected?(Int64(bitPattern: expectedContentLength))
        }
    }

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        MainActor.assumeIsolated {
            onDownloadReceived?(Int64(bitPattern: length))
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        MainActor.assumeIsolated {
            onPhaseChange?(.extracting)
        }
    }

    // MARK: - Extraction

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {
        MainActor.assumeIsolated {
            onExtractionProgress?(progress)
        }
    }

    // MARK: - Install

    nonisolated func showReady(toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void) {
        MainActor.assumeIsolated {
            onPhaseChange?(.readyToInstall(reply: reply))
        }
    }

    nonisolated func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping @Sendable () -> Void
    ) {
        MainActor.assumeIsolated {
            onPhaseChange?(.installing)
        }
    }

    nonisolated func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping @Sendable () -> Void
    ) {
        MainActor.assumeIsolated {
            onPhaseChange?(.done(acknowledge: acknowledgement))
        }
    }

    // MARK: - Cleanup

    nonisolated func dismissUpdateInstallation() {
        MainActor.assumeIsolated {
            onDismiss?()
        }
    }

    // No-op: the overlay lives inside the panel which is always accessible.
    nonisolated func showUpdateInFocus() {}
}

// MARK: - Markdown → HTML

/// Minimal markdown-to-HTML converter for release note descriptions.
/// Handles headings (###), bold (**), unordered lists (- / *), and paragraphs.
private func markdownToHTML(_ markdown: String) -> String {
    var html = ""
    var inList = false

    for line in markdown.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            if inList { html += "</ul>"; inList = false }
            html += "<h3>\(escape(String(trimmed.dropFirst(4))))</h3>"
        } else if trimmed.hasPrefix("## ") {
            if inList { html += "</ul>"; inList = false }
            html += "<h2>\(escape(String(trimmed.dropFirst(3))))</h2>"
        } else if trimmed.hasPrefix("# ") {
            if inList { html += "</ul>"; inList = false }
            html += "<h1>\(escape(String(trimmed.dropFirst(2))))</h1>"
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            if !inList { html += "<ul>"; inList = true }
            html += "<li>\(inlineMarkdown(String(trimmed.dropFirst(2))))</li>"
        } else if trimmed.isEmpty {
            if inList { html += "</ul>"; inList = false }
        } else {
            if inList { html += "</ul>"; inList = false }
            html += "<p>\(inlineMarkdown(trimmed))</p>"
        }
    }
    if inList { html += "</ul>" }
    return html
}

private func inlineMarkdown(_ text: String) -> String {
    var result = escape(text)
    // **bold**
    result = result.replacingOccurrences(
        of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>",
        options: .regularExpression)
    // *italic*
    result = result.replacingOccurrences(
        of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, with: "<em>$1</em>",
        options: .regularExpression)
    return result
}

private func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

