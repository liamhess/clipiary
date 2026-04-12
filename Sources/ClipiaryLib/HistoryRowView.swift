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
    let item: HistoryItem
    let maxPasteCount: Int
    let isSelected: Bool
    let showAppIcons: Bool
    let showItemDetails: Bool
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

    var body: some View {
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
        .onTapGesture(count: 2) {
            appState.selectedHistoryItemID = item.id
            appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
        }
        .onTapGesture {
            appState.selectedHistoryItemID = item.id
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            contextMenuItems
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

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Paste") {
            appState.selectedHistoryItemID = item.id
            appState.requestPasteSelected(plainTextOnly: !appState.settings.richTextPasteDefault)
        }
        Button("Paste as Plain Text") {
            appState.selectedHistoryItemID = item.id
            appState.requestPasteSelected(plainTextOnly: true)
        }
        if item.rtfData != nil || item.htmlData != nil {
            Button("Paste as Markdown") {
                appState.selectedHistoryItemID = item.id
                appState.requestMarkdownPaste()
            }
            Button("Paste Raw Source") {
                appState.selectedHistoryItemID = item.id
                appState.requestRawSourcePaste()
            }
        }
        Divider()
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            appState.selectedHistoryItemID = item.id
            appState.toggleFavoriteSelectedItem()
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

    func add(_ title: String, tag: String) {
        let mi = NSMenuItem(title: title, action: #selector(ContextMenuHandler.handleItem(_:)), keyEquivalent: "")
        mi.representedObject = tag
        mi.isEnabled = true
        menu.addItem(mi)
    }

    let pasteTitle = appState.settings.richTextPasteDefault ? "Paste (Rich Text)" : "Paste (Plain Text)"
    add(pasteTitle, tag: "paste")
    add("Paste as Plain Text", tag: "plain")
    if item.rtfData != nil || item.htmlData != nil {
        add("Paste as Markdown", tag: "markdown")
        add("Paste Raw Source", tag: "raw")
    }
    menu.addItem(.separator())
    add(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", tag: "favorite")

    return menu
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
    var mainAttr = AttributedString(string)
    var glowAttr: AttributedString? = glowColor != nil ? AttributedString(string) : nil
    if glowColor != nil { glowAttr!.foregroundColor = .clear }
    for term in terms {
        var start = string.startIndex
        while let range = string.range(of: term, options: [.caseInsensitive], range: start..<string.endIndex) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: mainAttr),
               let attrEnd = AttributedString.Index(range.upperBound, within: mainAttr) {
                mainAttr[attrStart..<attrEnd].foregroundColor = foreground
                if let background { mainAttr[attrStart..<attrEnd].backgroundColor = background }
                mainAttr[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
                glowAttr?[attrStart..<attrEnd].foregroundColor = glowColor
                glowAttr?[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
            }
            start = range.upperBound
        }
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
