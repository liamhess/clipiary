import AppKit
import SwiftUI

struct PanelRootView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case favorites = "Favorites"

        var id: Self { self }
    }

    @Environment(AppState.self) private var appState
    @FocusState private var searchFocused: Bool
    @State private var hoveredItemID: HistoryItem.ID?
    @State private var selectedTab: Tab = .history
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 12) {
            header
            historySection
            settingsSection
            footer
        }
        .padding(12)
        .frame(width: 376, height: 520)
        .background(panelBackground)
        .task {
            searchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text("Clipiary")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            tabBar
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedTab.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Search") {
                        searchQuery = ""
                        searchFocused = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Text("\(activeItems.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if selectedTab == .history || !favoriteItems.isEmpty {
                searchField
            }

            ScrollView {
                VStack(spacing: 12) {
                    if activeItems.isEmpty {
                        emptyState
                    } else {
                        if selectedTab == .history {
                            historyGroup(title: "Recent Copies", items: historyItems)
                        } else {
                            historyGroup(title: "Saved Favorites", items: favoriteItems)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(panelFill)
            )
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capture")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !appState.permissionManager.isTrusted {
                    Button("Grant Accessibility Access") {
                        appState.refreshAutoSelectPermissions()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Monitor normal copy events", isOn: Binding(
                    get: { appState.settings.isClipboardMonitoringEnabled },
                    set: { appState.settings.isClipboardMonitoringEnabled = $0 }
                ))
                Toggle("Autoselect highlighted text", isOn: Binding(
                    get: { appState.settings.isAutoSelectEnabled },
                    set: { appState.settings.isAutoSelectEnabled = $0 }
                ))
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            HStack(spacing: 12) {
                settingMetric(
                    title: "Minimum selection",
                    value: "\(appState.settings.minimumSelectionLength)"
                ) {
                    Stepper("", value: Binding(
                        get: { appState.settings.minimumSelectionLength },
                        set: { appState.settings.minimumSelectionLength = max(1, $0) }
                    ), in: 1...10)
                    .labelsHidden()
                }
                settingMetric(
                    title: "Cooldown",
                    value: "\(appState.settings.autoSelectCooldownMilliseconds) ms"
                ) {
                    Stepper("", value: Binding(
                        get: { appState.settings.autoSelectCooldownMilliseconds },
                        set: { appState.settings.autoSelectCooldownMilliseconds = min(max(100, $0), 2000) }
                    ), in: 100...2000, step: 50)
                    .labelsHidden()
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelFill)
        )
    }

    private var footer: some View {
        HStack {
            accessibilityStatus
            Spacer()
            Button("Clear History") {
                appState.history.clearNonFavorites()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            HStack {
                Text("\(appState.history.items.count)")
                Text("items")
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 2)
    }

    private var accessibilityStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.permissionManager.isTrusted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                .frame(width: 6, height: 6)
            if appState.permissionManager.isTrusted {
                Text(appState.settings.isAutoSelectEnabled ? "Autoselect ready" : "Clipboard only")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Button("Accessibility Required") {
                    appState.refreshAutoSelectPermissions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $searchQuery)
            .textFieldStyle(.plain)
            .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(panelFill)
        )
    }

    private func historyGroup(title: String, items: [HistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 8)

            VStack(spacing: 2) {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        }
    }

    private func row(for item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appState.restore(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.source == .autoSelect ? "cursorarrow.rays" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.source == .autoSelect ? Color.accentColor : .secondary)
                            .frame(width: 14, alignment: .center)

                        Text(item.displayText.isEmpty ? "Untitled" : item.displayText)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    appState.history.toggleFavorite(item)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? Color.accentColor : .secondary)
                .opacity(hoveredItemID == item.id || item.isFavorite ? 1 : 0.55)

                Button {
                    appState.history.delete(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hoveredItemID == item.id ? 1 : 0.45)
            }

            HStack(spacing: 6) {
                Text(item.appName)
                Text(item.source == .autoSelect ? "Selection" : "Clipboard")
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(for: item))
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredItemID = isHovered ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.system(size: 13, weight: .medium))
            Text(emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
    }

    private func rowBackground(for item: HistoryItem) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hoveredItemID == item.id ? hoverFill : Color.clear)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
    }

    private var panelFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }

    private var hoverFill: Color {
        Color.accentColor.opacity(0.09)
    }

    private var historyItems: [HistoryItem] {
        filteredItemsForSelectedTab(tab: .history)
    }

    private var favoriteItems: [HistoryItem] {
        filteredItemsForSelectedTab(tab: .favorites)
    }

    private var activeItems: [HistoryItem] {
        selectedTab == .history ? historyItems : favoriteItems
    }

    private var filteredItems: [HistoryItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appState.history.items
        }

        return appState.history.items.filter { item in
            item.text.localizedCaseInsensitiveContains(query) ||
            item.appName.localizedCaseInsensitiveContains(query) ||
            (item.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func filteredItemsForSelectedTab(tab: Tab) -> [HistoryItem] {
        switch tab {
        case .history:
            return filteredItems.filter { !$0.isFavorite }
        case .favorites:
            return filteredItems.filter(\.isFavorite)
        }
    }

    private var emptyMessage: String {
        switch selectedTab {
        case .history:
            return "Copy something, or enable autoselect to capture highlighted text."
        case .favorites:
            return "Mark important items as favorites so they stay separate from the stream."
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .history:
            return "No clipboard history yet"
        case .favorites:
            return "No favorites yet"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = tab == selectedTab
        let count = tab == .history ? historyItems.count : favoriteItems.count

        return Button {
            selectedTab = tab
            searchFocused = true
        } label: {
            HStack(spacing: 6) {
                Text(tab.rawValue)
                Text("\(count)")
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.7) : Color.secondary)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? panelFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private func settingMetric<Control: View>(title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
    }
}
