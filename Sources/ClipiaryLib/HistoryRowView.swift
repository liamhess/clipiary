import AppKit
import SwiftUI

@MainActor
let appIconCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 100
    return cache
}()

@MainActor
func appIcon(for bundleID: String?) -> NSImage? {
    guard let bundleID else { return nil }
    let key = bundleID as NSString
    if let cached = appIconCache.object(forKey: key) { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    appIconCache.setObject(icon, forKey: key)
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

    @MainActor static func trackBodyEval() {
        guard debugPerfEnabled else { return }
        if bodyEvalCount == 0 { bodyEvalStart = CFAbsoluteTimeGetCurrent() }
        bodyEvalCount += 1
        DispatchQueue.main.async {
            guard bodyEvalCount > 0 else { return }
            let ms = (CFAbsoluteTimeGetCurrent() - bodyEvalStart) * 1000
            print("[PERF] HistoryRowView.body: \(bodyEvalCount) rows in \(String(format: "%.1f", ms))ms")
            bodyEvalCount = 0
        }
    }

    let item: HistoryItem
    let maxPasteCount: Int
    let isSelected: Bool
    let showAppIcons: Bool
    let showItemDetails: Bool
    let showCharCountBadge: Bool
    let sizeBarScheme: String
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
        let _ = Self.trackBodyEval()
        VStack(alignment: .leading, spacing: theme.spacing.rowDetailsSpacing) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appState.selectedHistoryItemID = item.id
                    appState.restore(item)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            if showAppIcons, let icon = appIcon(for: item.bundleID) {
                                Image(nsImage: icon)
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
                                .shadow(color: activeTextGlow?.color ?? .clear, radius: activeTextGlow?.radius ?? 0)
                                .shadow(color: activeTextGlow?.innerColor ?? .clear, radius: activeTextGlow?.innerRadius ?? 0)
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
                        Image(systemName: "xmark")
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

            if showItemDetails {
                HStack(spacing: 6) {
                    highlightedText(item.appName, terms: searchTerms, foreground: theme.resolvedSearchHighlight, background: theme.resolvedSearchHighlightBackground)
                    Text(item.source == .copyOnSelect ? "(via Selection)" : "(via Clipboard)")
                    Text(Calendar.current.isDateInToday(item.createdAt)
                        ? "Today, \(item.createdAt.formatted(date: .omitted, time: .shortened))"
                        : item.createdAt.formatted(date: .abbreviated, time: .shortened))
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
        .background(RowNSViewCapture { rowNSView = $0 })
        .anchorPreference(key: SelectedRowAnchorKey.self, value: .bounds) { anchor in
            isSelected ? anchor : nil
        }
        .background {
            if isSelected {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: SelectedRowRectKey.self, value: geo.frame(in: .named("scrollArea")))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                .fill(rowFill)
        )
        .overlay {
            let border = theme.resolvedSelectedRowBorder
            if isSelected, border.isVisible {
                if border.animation == "sweep" {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let elapsed = sweepStartDate.map { timeline.date.timeIntervalSince($0) } ?? 0
                        let duration = border.animationDuration
                        let p = min(elapsed / duration, 0.7)
                        ZStack {
                            // Static full border always visible
                            RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                                .stroke(border.color, style: border.strokeStyle)
                            // Two bright pulses: A from top-left, B from bottom-right, meeting in the middle
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
        .onChange(of: isSelected) { _, selected in
            let border = theme.resolvedSelectedRowBorder
            if selected, border.animation == "flash" {
                borderFlash = 1.0
                withAnimation(.easeOut(duration: border.animationDuration).delay(0.05)) { borderFlash = 0 }
            }
            if selected { appState.selectedRowAnchorView = rowNSView }
        }
        .onAppear {
            if isSelected { appState.selectedRowAnchorView = rowNSView }
        }
        .compositingGroup()
        .overlay {
            if let glow = activeGlow, let innerColor = glow.innerColor, let innerRadius = glow.innerRadius {
                RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                    .fill(innerColor.opacity(0.25))
                    .blur(radius: innerRadius * 0.8)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: rowGlowColor, radius: rowGlowRadius)
        .shadow(color: rowInnerGlowColor, radius: rowInnerGlowRadius)
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

    private var rowGlowColor: Color {
        activeGlow?.color ?? .clear
    }

    private var rowGlowRadius: CGFloat {
        activeGlow?.radius ?? 0
    }

    private var rowInnerGlowColor: Color {
        activeGlow?.innerColor ?? .clear
    }

    private var rowInnerGlowRadius: CGFloat {
        activeGlow?.innerRadius ?? 0
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
        let filled: Int = count >= 10_000 ? 5 : count >= 5_000 ? 4 : count >= 2_000 ? 3 : count >= 500 ? 2 : count >= 100 ? 1 : 0
        let totalSegments = 5
        let colors = PasteCountBarScheme.colors(for: sizeBarScheme)
        return HStack(spacing: 1.5) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: theme.cornerRadii.gauge)
                    .fill(index < filled ? colors[index] : theme.resolvedGaugeUnfilled)
                    .frame(width: 3, height: 10)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("\(count.compactCharCount) characters")
    }

    @ViewBuilder
    private var favoriteButton: some View {        if singleFavoriteTab, let tabName = singleFavoriteTabName {
            Button {
                appState.selectedHistoryItemID = item.id
                appState.toggleFavoriteTab(item, tabName: tabName)
                appState.ensureSelection()
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
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
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? theme.resolvedAccent : .secondary)
            .opacity(isHovered || item.isFavorite ? 1 : 0.55)
        }
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

private struct RowNSViewCapture: NSViewRepresentable {
    let onReady: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onReady(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { onReady(nsView) }
}

private func buildHighlightAttrs(
    _ string: String, terms: [String], foreground: Color, background: Color?, glowColor: Color?
) -> (main: AttributedString, glow: AttributedString?) {
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

@ViewBuilder
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
