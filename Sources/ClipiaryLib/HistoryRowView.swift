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

struct HistoryRowView: View {
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
    let appState: AppState

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private var searchTerms: [String] {
        appState.searchQuery
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                                    .foregroundStyle(item.isImage ? theme.resolvedImageIndicator : item.source == .copyOnSelect ? theme.resolvedAccent : .secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            highlightedText(
                                item.displayText.isEmpty ? "Untitled" : item.displayText,
                                terms: item.displayText.isEmpty ? [] : searchTerms,
                                foreground: theme.resolvedSearchHighlight,
                                background: theme.resolvedSearchHighlightBackground
                            )
                                .font(item.isMonospace
                                    ? .system(size: 12, design: .monospaced)
                                    : .system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(itemLineLimit)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ForEach(favoriteTabNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0.45)
                }
            }

            if let description = item.snippetDescription, !description.isEmpty {
                highlightedText(description, terms: searchTerms, foreground: theme.resolvedSearchHighlight, background: theme.resolvedSearchHighlightBackground)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 22)
            }

            if showItemDetails {
                HStack(spacing: 6) {
                    highlightedText(item.appName, terms: searchTerms, foreground: theme.resolvedSearchHighlight, background: theme.resolvedSearchHighlightBackground)
                    Text(item.source == .copyOnSelect ? "Selection" : "Clipboard")
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, theme.spacing.rowHorizontalPadding)
        .padding(.vertical, theme.spacing.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(item.id)
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
                RoundedRectangle(cornerRadius: theme.cornerRadii.row, style: .continuous)
                    .stroke(border.color, style: border.strokeStyle)
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
        .shadow(color: rowGlowColor, radius: rowGlowRadius)
        .shadow(color: rowInnerGlowColor, radius: rowInnerGlowRadius)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedHistoryItemID = item.id
        }
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
    private var favoriteButton: some View {
        if singleFavoriteTab, let tabName = singleFavoriteTabName {
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

private func highlightedText(_ string: String, terms: [String], foreground: Color, background: Color?) -> Text {
    guard !terms.isEmpty else { return Text(string) }
    var attr = AttributedString(string)
    for term in terms {
        var start = string.startIndex
        while let range = string.range(of: term, options: [.caseInsensitive], range: start..<string.endIndex) {
            if let attrStart = AttributedString.Index(range.lowerBound, within: attr),
               let attrEnd = AttributedString.Index(range.upperBound, within: attr) {
                attr[attrStart..<attrEnd].foregroundColor = foreground
                if let background { attr[attrStart..<attrEnd].backgroundColor = background }
                attr[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
            }
            start = range.upperBound
        }
    }
    return Text(attr)
}
