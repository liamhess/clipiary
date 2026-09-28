import AppKit
import SwiftUI

// Plain dictionary instead of NSCache: NSCache evicts under memory pressure (e.g. sleep/wake).
@MainActor
var appIconStore: [String: CGImage] = [:]

// Rasterize into a CGBitmapContext and extract the CGImage directly. Storing CGImage
// (not NSImage) in the cache means SwiftUI's Image(decorative:scale:) gets a plain pixel
// buffer and uploads it to Metal without going through NSImage.cgImage(forProposedRect:)
// on every render pass, which is what causes the 100-900ms spikes on cache-hit rows.
@MainActor
private func prerasterize(_ image: NSImage, size: CGFloat = 32) -> CGImage? {
    let physical = Int(size * 2)
    guard let ctx = CGContext(
        data: nil,
        width: physical,
        height: physical,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return nil }
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    nsCtx.imageInterpolation = NSImageInterpolation.high
    image.draw(in: NSRect(x: 0, y: 0, width: physical, height: physical))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

@MainActor
func appIcon(for bundleID: String?) -> CGImage? {
    guard let bundleID else { return nil }
    if let cached = appIconStore[bundleID] { return cached }
    let t0 = debugPerfEnabled ? CFAbsoluteTimeGetCurrent() : 0
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let raw = NSWorkspace.shared.icon(forFile: url.path)
    if debugPerfEnabled {
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[PERF] appIcon miss: \(bundleID) \(String(format: "%.1f", ms))ms raw=\(Int(raw.size.width))x\(Int(raw.size.height))")
    }
    let t1 = debugPerfEnabled ? CFAbsoluteTimeGetCurrent() : 0
    guard let icon = prerasterize(raw) else { return nil }
    if debugPerfEnabled {
        let ms1 = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        print("[PERF] appIcon prerasterize: \(bundleID) \(String(format: "%.1f", ms1))ms -> \(icon.width)x\(icon.height)px")
    }
    if appIconStore.count >= 300 { appIconStore.removeAll() }
    appIconStore[bundleID] = icon
    return icon
}

struct SelectedRowAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct SelectedRowRectKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct HistoryRowView: View, Equatable {
    @MainActor private static var bodyEvalCount = 0
    @MainActor private static var bodyEvalStart: CFAbsoluteTime = 0
    @MainActor private static var lastRowStart: CFAbsoluteTime = 0
    @MainActor private static var lastRowDesc: String = ""
    @MainActor private static var slowRowCount = 0

    @MainActor static func trackBodyEval(desc: String) {
        guard debugPerfEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if bodyEvalCount > 0 {
            // Time from previous row's body start to this row's body start ≈ previous row's body cost.
            let prevMs = (now - lastRowStart) * 1000
            if prevMs > 3 {
                print("[PERF] slow row (\(String(format: "%.1f", prevMs))ms): \(lastRowDesc)")
                slowRowCount += 1
            }
        } else {
            bodyEvalStart = now
            slowRowCount = 0
        }
        lastRowStart = now
        lastRowDesc = desc
        bodyEvalCount += 1
        DispatchQueue.main.async {
            guard bodyEvalCount > 0 else { return }
            let ms = (CFAbsoluteTimeGetCurrent() - bodyEvalStart) * 1000
            // Also account for the last row's cost (from its start to now).
            let lastMs = (CFAbsoluteTimeGetCurrent() - lastRowStart) * 1000
            if lastMs > 3 {
                print("[PERF] slow row (\(String(format: "%.1f", lastMs))ms): \(lastRowDesc) [last]")
                slowRowCount += 1
            }
            let slowSuffix = slowRowCount > 0 ? " (\(slowRowCount) slow)" : ""
            print("[PERF] HistoryRowView.body: \(bodyEvalCount) rows in \(String(format: "%.1f", ms))ms\(slowSuffix), nsViewMakes=\(rowNSViewMakeCount)")
            bodyEvalCount = 0
            slowRowCount = 0
            rowNSViewMakeCount = 0
        }
    }

    let item: HistoryItem
    let maxPasteCount: Int
    let isSelected: Bool
    let showAppIcons: Bool
    let showItemDetails: Bool
    let showCharCountBadge: Bool
    let sizeBarScheme: String
    let sizeBarThresholds: [Int]
    let pasteCountBarScheme: String
    let singleFavoriteTab: Bool
    let singleFavoriteTabName: String?
    let showingFavoriteTabPicker: Bool
    let favoriteTabNames: [String]
    let itemLineLimit: Int
    let searchTerms: [String]
    let appState: AppState

    nonisolated static func == (lhs: HistoryRowView, rhs: HistoryRowView) -> Bool {
        lhs.item == rhs.item &&
        lhs.maxPasteCount == rhs.maxPasteCount &&
        lhs.isSelected == rhs.isSelected &&
        lhs.showAppIcons == rhs.showAppIcons &&
        lhs.showItemDetails == rhs.showItemDetails &&
        lhs.showCharCountBadge == rhs.showCharCountBadge &&
        lhs.sizeBarScheme == rhs.sizeBarScheme &&
        lhs.sizeBarThresholds == rhs.sizeBarThresholds &&
        lhs.pasteCountBarScheme == rhs.pasteCountBarScheme &&
        lhs.singleFavoriteTab == rhs.singleFavoriteTab &&
        lhs.singleFavoriteTabName == rhs.singleFavoriteTabName &&
        lhs.showingFavoriteTabPicker == rhs.showingFavoriteTabPicker &&
        lhs.favoriteTabNames == rhs.favoriteTabNames &&
        lhs.itemLineLimit == rhs.itemLineLimit &&
        lhs.searchTerms == rhs.searchTerms
    }

    @Environment(\.theme) private var theme
    @State private var isHovered = false
    @State private var borderFlash: Double = 0
    @State private var sweepStartDate: Date? = nil
    @State private var rowNSView: NSView?
    @State private var lastTapDate: Date? = nil

    var body: some View {
        let _bodyT0 = debugPerfEnabled ? CFAbsoluteTimeGetCurrent() : 0
        let _ = Self.trackBodyEval(desc: "\(item.bundleID ?? "?") icon=\(showAppIcons) search=\(!searchTerms.isEmpty) len=\(item.displayText.count) mono=\(item.isMonospace)")
        let _icon: CGImage? = showAppIcons ? appIcon(for: item.bundleID) : nil
        let _iconMs = debugPerfEnabled ? (CFAbsoluteTimeGetCurrent() - _bodyT0) * 1000 : 0
        let _ = debugPerfEnabled && _iconMs > 2 ? print("[PERF] body.icon: \(item.bundleID ?? "?") \(String(format: "%.1f", _iconMs))ms") : ()
        VStack(alignment: .leading, spacing: theme.spacing.rowDetailsSpacing) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appState.selectedHistoryItemID = item.id
                    appState.restore(item)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            if let icon = _icon {
                                Image(decorative: icon, scale: 2.0)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: item.isImage ? "photo" : item.source == .copyOnSelect ? "cursorarrow.rays" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(item.isImage ? theme.resolvedImageIndicator : item.source == .copyOnSelect ? theme.resolvedAccent : theme.resolvedTextSecondary)
                                    .frame(width: 16, height: 16, alignment: .center)
                            }
                            if showAppIcons, item.source == .copyOnSelect {
                                Image(systemName: "cursorarrow.rays")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(theme.resolvedAccent)
                                    .offset(x: 4, y: 4)
                            }
                        }

                        if item.isImage {
                            HStack(spacing: 5) {
                                Image(systemName: "photo")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.resolvedImageIndicator)
                                Text(item.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.resolvedTextSecondary)
                            }
                        } else {
                            highlightedText(
                                item.displayText.isEmpty ? "Untitled" : item.displayText,
                                terms: item.displayText.isEmpty ? [] : searchTerms,
                                foreground: theme.resolvedSearchHighlight,
                                background: theme.resolvedSearchHighlightBackground,
                                textGlow: theme.resolvedSearchHighlightTextGlow
                            )
                                .font(item.isMonospace ? theme.resolvedRowMonoFont : theme.resolvedRowFont)
                                .foregroundStyle(theme.resolvedTextPrimary)
                                .lineLimit(itemLineLimit)
                                .multilineTextAlignment(.leading)
                                .modifier(OptionalShadow(glow: activeTextGlow))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ForEach(favoriteTabNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.resolvedTextSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                    .fill(theme.resolvedPillBackground)
                            )
                    }

                    if let richLabel = item.rtfData != nil ? "RTF" : (item.htmlData != nil ? "HTML" : nil) {
                        Text(richLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.resolvedTextSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                    .fill(theme.resolvedPillBackground)
                            )
                    }

                    if let shortcut = item.globalShortcut {
                        Text(shortcut.displayString)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.resolvedTextSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                    .fill(theme.resolvedPillBackground)
                            )
                    }

                    if !item.isImage, sizeBarScheme != "none" {
                        sizeBarGauge
                    }

                    if !item.isImage, showCharCountBadge {
                        Text(item.textCount.compactCharCount)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.resolvedTextSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                    .fill(theme.resolvedPillBackground)
                            )
                    }

                    if pasteCountBarScheme != "none" {
                        pasteFrequencyGauge
                    }

                    favoriteButton

                    Button {
                        appState.selectedHistoryItemID = item.id
                        appState.history.delete(item)
                        appState.ensureSelection()
                    } label: {
                        Text(Image(systemName: "xmark"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.resolvedTextSecondary)
                    .opacity(isHovered ? 1 : 0.45)
                }
            }

            if let description = item.snippetDescription, !description.isEmpty {
                highlightedText(description, terms: searchTerms, foreground: theme.resolvedSearchHighlight, background: theme.resolvedSearchHighlightBackground, textGlow: theme.resolvedSearchHighlightTextGlow)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.resolvedTextSecondary)
                    .lineLimit(1)
                    .padding(.leading, 22)
            }

            if let urlString = item.referenceURL, let url = URL(string: urlString) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text(urlString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.resolvedAccent)
                .padding(.leading, 22)
                .onTapGesture {
                    NSWorkspace.shared.open(url)
                }
            }

            if showItemDetails {
                HStack(spacing: 6) {
                    Text(Calendar.current.isDateInToday(item.createdAt)
                        ? "Today, \(item.createdAt.formatted(date: .omitted, time: .shortened))"
                        : item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    highlightedText(item.appName, terms: searchTerms, foreground: theme.resolvedSearchHighlight, background: theme.resolvedSearchHighlightBackground)
                    Text(item.source == .copyOnSelect ? "(via Selection)" : "(via Clipboard)")
                    Text("·  \(item.textCount.compactCharCount) chars")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.resolvedTextTertiary)
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, theme.spacing.rowHorizontalPadding)
        .padding(.vertical, theme.spacing.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(item.id)
        .background {
            // Only the selected row needs an AppKit anchor NSView (for positioning the
            // right-click context menu — see AppDelegate.showContextMenuForSelectedItem).
            // Bridging an NSViewRepresentable into EVERY visible lazy row hosts an
            // AppKit-backed layer per row; that layer work lands in the render/CA-commit
            // pipeline (invisible to body timing) and balloons on the degraded compositor
            // path after display sleep/wake. Gating on isSelected keeps at most one.
            if isSelected {
                // onReady is the authoritative source for the selected row's anchor:
                // the capture only exists while isSelected, and makeNSView's async
                // callback is the first moment the NSView is available. Setting the
                // anchor here (rather than relying on onChange/onAppear reading
                // rowNSView) avoids the race where isSelected flips true before the
                // NSView has been bridged — which left selectedRowAnchorView nil and
                // broke the Cmd+Return context menu.
                RowNSViewCapture { view in
                    rowNSView = view
                    if isSelected { appState.selectedRowAnchorView = view }
                }
            }
        }
        .background {
            // Emit the selected-row anchor ONLY for the selected row. Attaching an
            // anchorPreference to every row (even one that returns nil) registers every row
            // as a preference source, which forces the enclosing LazyVStack to materialize
            // ALL filtered rows on each pass — defeating virtualization and turning a
            // ~20-row commit into a full-list commit (the multi-hundred-ms exit→entry CA
            // stalls). Mirrors the SelectedRowRectKey pattern below, which is lazy-friendly.
            if isSelected {
                Color.clear
                    .anchorPreference(key: SelectedRowAnchorKey.self, value: .bounds) { $0 }
            }
        }
        .background {
            if isSelected {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: SelectedRowRectKey.self, value: geo.frame(in: .named("scrollArea")))
                }
            }
        }
        .background {
            let cornerRadius = theme.cornerRadii.row
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(rowFill)
                if isSelected, theme.fills.rowSelected.texture != nil {
                    TextureOverlay(fill: theme.fills.rowSelected, themesDirectory: appState.themeManager.themesDirectoryURL)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else if isHovered, theme.fills.rowHovered.texture != nil {
                    TextureOverlay(fill: theme.fills.rowHovered, themesDirectory: appState.themeManager.themesDirectoryURL)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .modifier(OptionalShadow(glow: activeGlow))
        }
        .overlay {
            let border = theme.resolvedSelectedRowBorder
            if isSelected, border.isVisible {
                if border.animation == "sweep" {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let elapsed = sweepStartDate.map { timeline.date.timeIntervalSince($0) } ?? 0
                        let duration = border.animationDuration
                        let p = min(elapsed / duration, 0.7)
                        ZStack {
                            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                                .stroke(border.color, style: border.strokeStyle)
                            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                                .trim(from: max(0, p - 0.2), to: min(p, 0.5))
                                .stroke(border.color, style: StrokeStyle(lineWidth: border.width))
                                .brightness(0.7)
                            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                                .trim(from: 0.5 + max(0, p - 0.2), to: 0.5 + min(p, 0.5))
                                .stroke(border.color, style: StrokeStyle(lineWidth: border.width))
                                .brightness(0.7)
                        }
                    }
                    .onAppear { sweepStartDate = Date() }
                    .onDisappear { sweepStartDate = nil }
                } else {
                    RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                        .stroke(border.color, style: border.strokeStyle)
                        .brightness(border.animation == "flash" ? borderFlash : 0)
                }
            }
        }
        .overlay {
            if let glow = activeGlow, let innerColor = glow.innerColor, let innerRadius = glow.innerRadius {
                RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                    .fill(innerColor.opacity(0.25))
                    .blur(radius: innerRadius * 0.8)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isSelected) { _, selected in
            let border = theme.resolvedSelectedRowBorder
            if selected, border.animation == "flash" {
                borderFlash = 1.0
                withAnimation(.easeOut(duration: border.animationDuration).delay(0.05)) { borderFlash = 0 }
            }
            if selected, let v = rowNSView { appState.selectedRowAnchorView = v }
        }
        .onAppear {
            if isSelected, let v = rowNSView { appState.selectedRowAnchorView = v }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            appState.selectedHistoryItemID = item.id
            appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
        })
        .simultaneousGesture(TapGesture().onEnded {
            let now = Date()
            let isDouble = lastTapDate.map { now.timeIntervalSince($0) < NSEvent.doubleClickInterval } ?? false
            lastTapDate = now
            appState.selectedHistoryItemID = item.id
            if isDouble {
                appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
            }
        })
        .onHover { hovering in
            isHovered = hovering
        }
        .modifier(BodyEndTracker(start: _bodyT0, desc: "\(item.bundleID ?? "?")"))
    }

    private var rowFill: AnyShapeStyle {
        if isSelected {
            return theme.resolvedRowSelectedFill
        }
        if isHovered {
            return theme.resolvedRowHoveredFill
        }
        return AnyShapeStyle(Color.clear)
    }

    private var activeGlow: Theme.ResolvedGlow? {
        if isSelected { return theme.resolvedSelectedRowGlow }
        if isHovered { return theme.resolvedHoveredRowGlow }
        return nil
    }

    private var activeTextGlow: Theme.ResolvedGlow? {
        if isSelected { return theme.resolvedSelectedRowTextGlow }
        if isHovered { return theme.resolvedHoveredRowTextGlow }
        return nil
    }

    private var pasteFrequencyGauge: some View {
        let colors = PasteCountBarScheme.colors(for: pasteCountBarScheme)
        let totalSegments = 5
        let filled = item.pasteCount > 0
            ? max(1, Int(round(Double(item.pasteCount) / Double(maxPasteCount) * Double(totalSegments))))
            : 0
        let tooltipText = item.pasteCount > 0 ? "\(item.pasteCount)x pasted" : "Not yet pasted"

        return HStack(spacing: 1.5) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: theme.cornerRadii.gauge)
                    .fill(index < filled ? colors[index] : theme.resolvedGaugeUnfilled)
                    .frame(width: 3, height: 10)
            }
        }
        .opacity(item.pasteCount > 0 ? 1 : 0.75)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(tooltipText)
    }

    private var sizeBarGauge: some View {
        let count = item.textCount
        let thresholds = sizeBarThresholds
        let filled = thresholds.reduce(0) { $0 + (count >= $1 ? 1 : 0) }
        let totalSegments = thresholds.count
        let colors = PasteCountBarScheme.colors(for: sizeBarScheme)
        return HStack(spacing: 1.5) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: theme.cornerRadii.gauge)
                    .fill(index < filled ? colors[index % max(colors.count, 1)] : theme.resolvedGaugeUnfilled)
                    .frame(width: 3, height: 10)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("\(count.compactCharCount) characters")
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if singleFavoriteTab, let tabName = singleFavoriteTabName {
            Button {
                appState.selectedHistoryItemID = item.id
                appState.toggleFavoriteTab(item, tabName: tabName)
                appState.ensureSelection()
            } label: {
                Text(Image(systemName: item.isFavorite ? "star.fill" : "star"))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? theme.resolvedAccent : .secondary)
            .opacity(isHovered || item.isFavorite ? 1 : 0.55)
        } else {
            Button {
                appState.selectedHistoryItemID = item.id
                appState.toggleFavoriteSelectedItem()
            } label: {
                Text(Image(systemName: item.isFavorite ? "star.fill" : "star"))
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? theme.resolvedAccent : .secondary)
            .opacity(isHovered || item.isFavorite ? 1 : 0.55)
        }
    }

}

/// Applies up to two shadow passes only when a glow is actually configured.
/// A plain `.shadow(color: .clear, radius: 0)` still promotes the view to a CA compositing
/// layer — skipping it entirely for non-glowing rows eliminates hundreds of layer ops per frame.
private struct OptionalShadow: ViewModifier {
    let glow: Theme.ResolvedGlow?
    func body(content: Content) -> some View {
        if let glow {
            content
                .shadow(color: glow.color, radius: glow.radius)
                .modifier(OptionalInnerShadow(glow: glow))
        } else {
            content
        }
    }
}

private struct OptionalInnerShadow: ViewModifier {
    let glow: Theme.ResolvedGlow
    func body(content: Content) -> some View {
        if let innerColor = glow.innerColor, let innerRadius = glow.innerRadius {
            content.shadow(color: innerColor, radius: innerRadius)
        } else {
            content
        }
    }
}

/// Logs body-construction time for a single row. Time captured here = SwiftUI calling body
/// + all modifier chain construction up to this point. If `trackBodyEval` reports a row was
/// "slow" but BodyEnd reports a fast time for it, the slowness is in SwiftUI's pipeline AFTER
/// body returns (layout/render/diff), not in our body code.
private struct BodyEndTracker: ViewModifier {
    let start: CFAbsoluteTime
    let desc: String
    func body(content: Content) -> some View {
        let _ = {
            guard debugPerfEnabled else { return }
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if ms > 3 { print("[PERF] body.end: \(desc) \(String(format: "%.1f", ms))ms") }
        }()
        return content
    }
}

@MainActor
final class ContextMenuHandler: NSObject {
    let item: HistoryItem
    let appState: AppState

    init(item: HistoryItem, appState: AppState) {
        self.item = item
        self.appState = appState
    }

    @objc func handleItem(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        appState.selectedHistoryItemID = item.id
        switch tag {
        case "paste":
            appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
        case "plain":
            appState.requestPasteSelected(plainTextOnly: true)
        case "markdown":
            appState.requestMarkdownPaste()
        case "raw":
            appState.requestRawSourcePaste()
        case "favorite":
            appState.toggleFavoriteSelectedItem()
        case "openurl":
            if let urlString = item.referenceURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
}

@MainActor
func buildMenu(item: HistoryItem, appState: AppState) -> NSMenu {
    let menu = NSMenu()

    func add(_ title: String, tag: String, key: String = "") {
        let mi = NSMenuItem(title: title, action: #selector(ContextMenuHandler.handleItem(_:)), keyEquivalent: key)
        mi.keyEquivalentModifierMask = []   // single letter, no modifier
        mi.representedObject = tag
        mi.isEnabled = true
        menu.addItem(mi)
    }

    let isRichDefault = appState.settings.richTextPasteDefault
    let pasteTitle = isRichDefault ? "Paste (Rich Text)" : "Paste (Plain Text)"
    // "r" for the rich-text default paste; when plain is the default the item
    // already sits at the top of the menu so it needs no extra mnemonic.
    add(pasteTitle, tag: "paste", key: isRichDefault ? "r" : "")
    add("Paste as Plain Text", tag: "plain", key: "p")
    if item.rtfData != nil || item.htmlData != nil {
        add("Paste as Markdown", tag: "markdown", key: "m")
        add("Paste Raw Source", tag: "raw", key: "s")
    }
    menu.addItem(.separator())
    if item.referenceURL != nil {
        add("Open Reference URL", tag: "openurl", key: "u")
    }
    add(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", tag: "favorite", key: "f")

    return menu
}

extension Int {
    var compactCharCount: String {
        switch self {
        case 0..<1_000: return "\(self)"
        case 1_000..<10_000:
            let k = Double(self) / 1_000
            return k.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(k))k" : String(format: "%.1fk", k)
        default:
            return "\(self / 1_000)k"
        }
    }
}

// Counts RowNSViewCapture.makeNSView calls (i.e. AppKit anchor NSViews bridged into the
// lazy list). Printed in the render-batch summary when perf debug is on: a healthy value is
// ~1 (only the selected row); a large value means the per-row AppKit bridge regressed.
@MainActor
var rowNSViewMakeCount = 0

private struct RowNSViewCapture: NSViewRepresentable {
    let onReady: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        if debugPerfEnabled { rowNSViewMakeCount += 1 }
        let v = NSView()
        DispatchQueue.main.async { onReady(v) }
        return v
    }
    // NSView identity is stable after makeNSView; calling onReady here would write @State
    // on every update cycle, scheduling unnecessary re-renders.
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private func buildHighlightAttrs(
    _ string: String, terms: [String], foreground: Color, background: Color?, glowColor: Color?
) -> (main: AttributedString, glow: AttributedString?) {
    let t0 = debugPerfEnabled ? CFAbsoluteTimeGetCurrent() : 0
    defer {
        if debugPerfEnabled {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if ms > 1 { print("[PERF] buildHighlightAttrs: \(String(format: "%.1f", ms))ms len=\(string.count) terms=\(terms)") }
        }
    }
    // Fast pre-check: if no term matches at all, skip AttributedString work entirely.
    let lowered = string.lowercased()
    let hasMatch = terms.contains { lowered.range(of: $0, options: .literal) != nil }
    guard hasMatch else {
        return (AttributedString(string), glowColor != nil ? {
            var a = AttributedString(string); a.foregroundColor = .clear; return a
        }() : nil)
    }

    var mainAttr = AttributedString(string)
    var glowAttr: AttributedString? = glowColor != nil ? AttributedString(string) : nil
    if glowColor != nil { glowAttr!.foregroundColor = .clear }
    let maxHighlights = 10
    var totalHighlights = 0
    for term in terms {
        // Single-char terms get a tighter per-term cap so they don't monopolise the
        // budget in multi-word queries (e.g. "k an" → "k" gets 3, "an" gets the rest).
        let termCap = term.count == 1 ? 3 : maxHighlights
        var termHighlights = 0
        var start = string.startIndex
        while let range = string.range(of: term, options: [.caseInsensitive], range: start..<string.endIndex) {
            if totalHighlights >= maxHighlights || termHighlights >= termCap { break }
            if let attrStart = AttributedString.Index(range.lowerBound, within: mainAttr),
               let attrEnd = AttributedString.Index(range.upperBound, within: mainAttr) {
                mainAttr[attrStart..<attrEnd].foregroundColor = foreground
                if let background { mainAttr[attrStart..<attrEnd].backgroundColor = background }
                mainAttr[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
                glowAttr?[attrStart..<attrEnd].foregroundColor = glowColor
                glowAttr?[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
                totalHighlights += 1
                termHighlights += 1
            }
            start = range.upperBound
        }
        if totalHighlights >= maxHighlights { break }
    }
    return (mainAttr, glowAttr)
}

@MainActor @ViewBuilder
private func highlightedText(_ string: String, terms: [String], foreground: Color, background: Color?, textGlow: Theme.ResolvedGlow? = nil) -> some View {
    if terms.isEmpty {
        Text(string)
    } else {
        let (mainAttr, glowAttr) = buildHighlightAttrs(string, terms: terms, foreground: foreground, background: background, glowColor: textGlow?.color)
        if let glow = textGlow, let ga = glowAttr {
            Text(mainAttr)
                .overlay(alignment: .topLeading) {
                    Text(ga)
                        .shadow(color: glow.color, radius: glow.radius)
                        .allowsHitTesting(false)
                }
        } else {
            Text(mainAttr)
        }
    }
}
