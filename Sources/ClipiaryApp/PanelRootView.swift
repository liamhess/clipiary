import AppKit
import SwiftUI

struct PanelRootView: View {
    private let cooldownOptions = [100, 200, 350, 500, 750, 1_000, 1_500, 2_000]
    private let historyLimitOptions = [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

    @Environment(AppState.self) private var appState
    @FocusState private var searchFocused: Bool
    @State private var hoveredItemID: HistoryItem.ID?
    @State private var settingsExpanded = false
    @State private var shortcutsHelpPresented = false

    var body: some View {
        VStack(spacing: 12) {
            header
            historySection
            settingsSection
            footer
        }
        .padding(12)
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(panelBackground)
        .task {
            appState.requestSearchFocus()
        }
        .onChange(of: appState.searchFocusRequestID) {
            searchFocused = true
        }
        .onChange(of: appState.popoverOpenRequestID) {
            settingsExpanded = false
            shortcutsHelpPresented = false
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
                Text(appState.selectedTab.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Search") {
                        appState.searchQuery = ""
                        appState.requestSearchFocus()
                        appState.ensureSelection()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Text("\(appState.activeItems.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            searchField

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if appState.activeItems.isEmpty {
                            emptyState
                        } else {
                            if appState.selectedTab == .history {
                                historyGroup(title: "Recent Copies", items: appState.historyItems)
                            } else {
                                historyGroup(title: "Saved Favorites", items: appState.favoriteItems)
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
                .onChange(of: appState.selectedHistoryItemID) {
                    guard let selectedID = appState.selectedHistoryItemID else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: settingsExpanded ? 10 : 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        settingsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: settingsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    shortcutsHelpPresented.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Keyboard shortcuts")
                .popover(isPresented: $shortcutsHelpPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    shortcutsHelpPopover
                }
            }

            if settingsExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !appState.permissionManager.isTrusted {
                        Button("Grant Accessibility Access") {
                            appState.refreshCopyOnSelectPermissions()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                    }

                    settingsToggleRow(
                        title: "Monitor normal copy events",
                        isOn: Binding(
                            get: { appState.settings.isClipboardMonitoringEnabled },
                            set: { appState.settings.isClipboardMonitoringEnabled = $0 }
                        )
                    )

                    settingsToggleRow(
                        title: "Move to top on paste",
                        isOn: Binding(
                            get: { appState.settings.moveToTopOnPaste },
                            set: { appState.settings.moveToTopOnPaste = $0 }
                        )
                    )

                    settingsToggleRow(
                        title: "Copy on select",
                        isOn: Binding(
                            get: { appState.settings.isCopyOnSelectEnabled },
                            set: { appState.settings.isCopyOnSelectEnabled = $0 }
                        )
                    )

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
                        value: nil
                    ) {
                        optionPicker(
                            selection: Binding(
                                get: { appState.settings.copyOnSelectCooldownMilliseconds },
                                set: { appState.settings.copyOnSelectCooldownMilliseconds = $0 }
                            ),
                            options: cooldownOptions,
                            label: { value in "\(value) ms" },
                            width: 94
                        )
                    }

                    settingMetric(
                        title: "History limit",
                        value: nil
                    ) {
                        optionPicker(
                            selection: Binding(
                                get: { appState.settings.historyLimit },
                                set: { appState.settings.historyLimit = $0 }
                            ),
                            options: historyLimitOptions,
                            label: { value in "\(value)" },
                            width: 94
                        )
                    }

                    settingMetric(
                        title: "Global shortcut",
                        value: appState.isRecordingShortcut ? "Press keys..." : appState.settings.globalShortcut.displayString
                    ) {
                        Button(appState.isRecordingShortcut ? "Cancel" : "Record") {
                            appState.isRecordingShortcut.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                    }
                }
                .transition(.opacity)
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
                Text(appState.settings.isCopyOnSelectEnabled ? "Copy-on-select ready" : "Clipboard only")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Button("Accessibility Required") {
                    appState.refreshCopyOnSelectPermissions()
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
            TextField("Search clipboard history", text: Binding(
                get: { appState.searchQuery },
                set: { appState.searchQuery = $0 }
            ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    appState.requestPasteSelected()
                }
                .onChange(of: appState.searchQuery) {
                    appState.ensureSelection()
                }
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                    appState.requestSearchFocus()
                    appState.ensureSelection()
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

            LazyVStack(spacing: 2) {
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
                    appState.selectedHistoryItemID = item.id
                    appState.restore(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.source == .copyOnSelect ? "cursorarrow.rays" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.source == .copyOnSelect ? Color.accentColor : .secondary)
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
                    appState.selectedHistoryItemID = item.id
                    appState.history.toggleFavorite(item)
                    appState.ensureSelection()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? Color.accentColor : .secondary)
                .opacity(hoveredItemID == item.id || item.isFavorite ? 1 : 0.55)

                Button {
                    appState.selectedHistoryItemID = item.id
                    appState.history.delete(item)
                    appState.ensureSelection()
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
                Text(item.source == .copyOnSelect ? "Selection" : "Clipboard")
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(item.id)
        .background(rowBackground(for: item))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedHistoryItemID = item.id
        }
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
            .fill(rowFill(for: item))
    }

    private var shortcutsHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                shortcutRow("Open Clipiary", appState.settings.globalShortcut.displayString)
                shortcutRow("Focus search", "Cmd F")
                shortcutRow("Favorite or unfavorite", "Cmd D")
                shortcutRow("Move selection", "Up / Down")
                shortcutRow("Switch tabs", "Left / Right")
                shortcutRow("Restore selected item", "Return")
                shortcutRow("Delete selected item", "Delete")
                shortcutRow("Close popover", "Esc")
            }
        }
        .padding(12)
        .frame(width: 260)
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

    private var emptyMessage: String {
        switch appState.selectedTab {
        case .history:
            return "Copy something, or enable copy-on-select to capture highlighted text."
        case .favorites:
            return "Mark important items as favorites so they stay separate from the stream."
        }
    }

    private var emptyTitle: String {
        switch appState.selectedTab {
        case .history:
            return "No clipboard history yet"
        case .favorites:
            return "No favorites yet"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppState.PopoverTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }

    private func tabButton(for tab: AppState.PopoverTab) -> some View {
        let isSelected = tab == appState.selectedTab
        let count = tab == .history ? appState.historyItems.count : appState.favoriteItems.count

        return Button {
            appState.setSelectedTab(tab)
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
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private func rowFill(for item: HistoryItem) -> Color {
        if appState.selectedHistoryItemID == item.id {
            return Color.accentColor.opacity(0.18)
        }

        if hoveredItemID == item.id {
            return hoverFill
        }

        return .clear
    }

    private func settingMetric<Control: View>(title: String, value: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let value {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold))
                }
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

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 12))
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
    }

    private func shortcutRow(_ title: String, _ shortcut: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
    }

    private func optionPicker(
        selection: Binding<Int>,
        options: [Int],
        label: @escaping (Int) -> String,
        width: CGFloat
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width)
    }
}
