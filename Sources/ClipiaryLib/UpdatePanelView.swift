import AppKit
import Sparkle
import SwiftUI

struct UpdatePanelView: View {
    @Environment(\.theme) private var theme
    private let manager = UpdaterManager.shared

    var body: some View {
        VStack(spacing: 12) {
            phaseContent
        }
        .padding(.horizontal, theme.spacing.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadii.contentArea, style: .continuous)
                .fill(theme.resolvedPanelFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadii.contentArea, style: .continuous))
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch manager.phase {
        case .idle:
            EmptyView()

        case .checking(let cancel):
            panelRow {
                ProgressView().progressViewStyle(.circular).controlSize(.small)
                Text("Checking for Updates\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
            } trailing: {
                plainButton("Cancel") { cancel() }
            }

        case .updateFound(let item, _, let reply):
            panelRow {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(theme.resolvedAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Version \(item.displayVersionString)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } trailing: {
                HStack(spacing: 10) {
                    plainButton("Later") { reply(.dismiss) }
                    accentButton(item.isInformationOnlyUpdate ? "Visit Website" : "Install") {
                        if item.isInformationOnlyUpdate, let url = item.infoURL {
                            NSWorkspace.shared.open(url)
                            reply(.dismiss)
                        } else {
                            reply(.install)
                        }
                    }
                }
            }
            if let html = manager.releaseNotesHTML {
                releaseNotesView(html: html)
            }
            if !item.isInformationOnlyUpdate {
                HStack {
                    Spacer()
                    plainButton("Skip This Version") { reply(.skip) }
                        .foregroundStyle(.secondary)
                }
            }

        case .notFound(let ack):
            panelRow {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(theme.resolvedStatusReady)
                Text("You\u{2019}re up to date.")
                    .font(.system(size: 12))
                Spacer()
            } trailing: {
                plainButton("OK") {
                    ack()
                    UpdaterManager.shared.phase = .idle
                }
            }

        case .downloading(let cancel):
            let expected = manager.downloadExpectedBytes
            let received = manager.downloadReceivedBytes
            VStack(spacing: 6) {
                panelRow {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(theme.resolvedAccent)
                    Text("Downloading\u{2026}")
                        .font(.system(size: 12))
                    Spacer()
                    if expected > 0 {
                        Text(downloadLabel(received: received, expected: expected))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    plainButton("Cancel") { cancel() }
                }
                if expected > 0 {
                    themedProgressBar(value: Double(received), total: Double(expected))
                } else {
                    themedProgressBar(value: nil, total: nil)
                }
            }

        case .extracting:
            VStack(spacing: 6) {
                panelRow {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                    Text("Extracting\u{2026}")
                        .font(.system(size: 12))
                    Spacer()
                } trailing: { EmptyView() }
                themedProgressBar(value: manager.extractionProgress, total: 1.0)
            }

        case .readyToInstall(let reply):
            panelRow {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(theme.resolvedAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Install")
                        .font(.system(size: 12, weight: .semibold))
                    Text("The app will relaunch.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } trailing: {
                HStack(spacing: 10) {
                    plainButton("Later") { reply(.dismiss) }
                    accentButton("Install") { reply(.install) }
                }
            }

        case .installing:
            panelRow {
                ProgressView().progressViewStyle(.circular).controlSize(.small)
                Text("Installing\u{2026}")
                    .font(.system(size: 12))
                Spacer()
            } trailing: { EmptyView() }

        case .done(let ack):
            panelRow {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.resolvedStatusReady)
                Text("Update Installed")
                    .font(.system(size: 12))
                Spacer()
            } trailing: {
                plainButton("OK") {
                    ack()
                    UpdaterManager.shared.phase = .idle
                }
            }

        case .error(let message, let ack):
            panelRow {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.resolvedStatusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Failed")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            } trailing: {
                plainButton("OK") {
                    ack()
                    UpdaterManager.shared.phase = .idle
                }
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func panelRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            leading()
            trailing()
        }
        .frame(minHeight: 24)
    }

    /// Themed horizontal progress bar using the theme's gauge radius and accent/unfilled colors.
    /// Pass nil value/total for an indeterminate animated shimmer.
    private func themedProgressBar(value: Double?, total: Double?) -> some View {
        let radius = theme.cornerRadii.gauge
        let filled = theme.resolvedAccent
        let unfilled = theme.resolvedGaugeUnfilled
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(unfilled)
                if let value, let total, total > 0 {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(filled)
                        .frame(width: max(radius * 2, geo.size.width * min(value / total, 1.0)))
                        .animation(.linear(duration: 0.1), value: value)
                } else {
                    // Indeterminate: sliding accent bar
                    IndeterminateBar(radius: radius, color: filled)
                }
            }
        }
        .frame(height: 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Release notes

    private func releaseNotesView(html: String) -> some View {
        Group {
            if let notes = attributedString(from: html) {
                ReleaseNotesTextView(attributedText: notes)
            }
        }
        .frame(maxHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func attributedString(from html: String) -> NSAttributedString? {
        let styled = """
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: 13px; margin: 0; }
        h1 { font-size: 18px; font-weight: 700; margin: 10px 0 4px 0; }
        h2 { font-size: 16px; font-weight: 700; margin: 9px 0 3px 0; }
        h3 { font-size: 15px; font-weight: 700; margin: 8px 0 3px 0; }
        p { margin: 2px 0; }
        ul { margin: 2px 0 8px 18px; padding-left: 0; }
        li { margin: 1px 0; }
        strong { font-weight: 600; }
        </style>
        \(html)
        """
        guard let data = styled.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else { return nil }
        let themed = NSMutableAttributedString(attributedString: nsAttr)
        let fullRange = NSRange(location: 0, length: themed.length)
        themed.addAttribute(.foregroundColor, value: NSColor(theme.resolvedTextPrimary), range: fullRange)
        applyReleaseNotesParagraphStyling(to: themed)
        return themed
    }

    private func applyReleaseNotesParagraphStyling(to text: NSMutableAttributedString) {
        let nsString = text.string as NSString
        var location = 0

        while location < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            let attributes = text.attributes(at: paragraphRange.location, effectiveRange: nil)
            let font = attributes[.font] as? NSFont
            let existingStyle = (attributes[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
            let style = existingStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()

            if let font, font.pointSize >= 15 {
                style.paragraphSpacingBefore = paragraphRange.location == 0 ? 0 : 8
                style.paragraphSpacing = 3
            } else {
                style.paragraphSpacingBefore = 0
            }

            text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            location = NSMaxRange(paragraphRange)
        }
    }

    // MARK: - Buttons

    private func accentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadii.tabButton, style: .continuous)
                        .fill(theme.resolvedAccent)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.resolvedAccent)
        }
        .buttonStyle(.plain)
    }

    private func downloadLabel(received: Int64, expected: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: received)) of \(formatter.string(fromByteCount: expected))"
    }
}

private struct ReleaseNotesTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> ReleaseNotesScrollView {
        let scrollView = ReleaseNotesScrollView()
        scrollView.apply(attributedText: attributedText)
        return scrollView
    }

    func updateNSView(_ nsView: ReleaseNotesScrollView, context: Context) {
        nsView.apply(attributedText: attributedText)
    }
}

private final class ReleaseNotesScrollView: NSScrollView {
    private let textView: NSTextView

    init() {
        let textView = NSTextView(frame: .zero)
        self.textView = textView
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true

        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor
        ]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0

        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }

        let width = contentSize.width
        textView.frame.size.width = width
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let totalHeight = ceil(usedHeight + (textView.textContainerInset.height * 2))
        textView.frame.size.height = max(totalHeight, contentSize.height)
    }

    func apply(attributedText: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributedText)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

private struct IndeterminateBar: View {
    let radius: CGFloat
    let color: Color
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .frame(width: geo.size.width * 0.35)
                .offset(x: offset * geo.size.width)
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        offset = 1
                    }
                }
        }
        .clipped()
    }
}
