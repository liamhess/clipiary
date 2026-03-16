import AppKit
import SwiftUI

private struct SelectedRowAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct PanelRootView: View {
    private let cooldownOptions = [100, 200, 350, 500, 750, 1_000, 1_500, 2_000]
    private let selectionBufferOptions = [1, 2, 3, 5, 10]
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
        .overlayPreferenceValue(SelectedRowAnchorKey.self) { anchor in
            if appState.showingFavoriteTabPicker {
                favoriteTabPickerOverlay(anchor: anchor)
            }
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
            searchField
                .frame(height: appState.settings.alwaysShowSearch || !appState.searchQuery.isEmpty ? nil : 0)
                .clipped()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if appState.activeItems.isEmpty {
                            emptyState
                        } else {
                            switch appState.selectedTab.kind {
                            case .history:
                                historyGroup(title: "Recent Copies", items: appState.historyItems)
                            case .favorites(let name):
                                historyGroup(title: name, items: appState.favoriteItems(for: name))
                            }
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .onAppear { overrideScrollerStyle() }
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
                        title: "Show item details",
                        isOn: Binding(
                            get: { appState.settings.showItemDetails },
                            set: { appState.settings.showItemDetails = $0 }
                        )
                    )

                    settingsToggleRow(
                        title: "Always show search field",
                        isOn: Binding(
                            get: { appState.settings.alwaysShowSearch },
                            set: { appState.settings.alwaysShowSearch = $0 }
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
                        title: "Keep unused copy-on-select items",
                        value: nil
                    ) {
                        optionPicker(
                            selection: Binding(
                                get: { appState.settings.copyOnSelectBufferLimit },
                                set: { appState.settings.copyOnSelectBufferLimit = $0 }
                            ),
                            options: selectionBufferOptions,
                            label: { value in "\(value)" },
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

                    settingMetric(
                        title: "Quick paste previous",
                        value: appState.isRecordingQuickPasteShortcut ? "Press keys..." : appState.settings.quickPasteShortcut.displayString
                    ) {
                        Button(appState.isRecordingQuickPasteShortcut ? "Cancel" : "Record") {
                            appState.isRecordingQuickPasteShortcut.toggle()
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
            Button {
                appState.history.clearNonFavorites()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("Clear History")
                }
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle")
                    Text("Quit")
                }
            }
            HStack(spacing: 3) {
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
                set: {
                    if $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appState.searchQuery = ""
                    } else {
                        appState.searchQuery = $0
                    }
                }
            ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(keys: [.upArrow, .downArrow]) { _ in .handled }
                .onKeyPress(.space) { appState.searchQuery.isEmpty ? .handled : .ignored }
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
        LazyVStack(spacing: 2) {
            ForEach(items) { item in
                row(for: item)
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
                        Image(systemName: item.isImage ? "photo" : item.source == .copyOnSelect ? "cursorarrow.rays" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.isImage ? Color.orange : item.source == .copyOnSelect ? Color.accentColor : .secondary)
                            .frame(width: 14, alignment: .center)

                        Text(item.displayText.isEmpty ? "Untitled" : item.displayText)
                            .font(item.isMonospace
                                ? .system(size: 12, design: .monospaced)
                                : .system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                favoriteButton(for: item)

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

            if appState.settings.showItemDetails {
                HStack(spacing: 6) {
                    Text(item.appName)
                    Text(item.source == .copyOnSelect ? "Selection" : "Clipboard")
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(item.id)
        .anchorPreference(key: SelectedRowAnchorKey.self, value: .bounds) { anchor in
            appState.showingFavoriteTabPicker && appState.selectedHistoryItemID == item.id ? anchor : nil
        }
        .background(rowBackground(for: item))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedHistoryItemID = item.id
        }
        .onHover { isHovered in
            hoveredItemID = isHovered ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
        .popover(
            isPresented: Binding(
                get: { appState.isPreviewVisible && appState.selectedHistoryItemID == item.id },
                set: { if !$0 { appState.isPreviewVisible = false } }
            ),
            arrowEdge: .trailing
        ) {
            itemPreview(for: item)
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

    private func itemPreview(for item: HistoryItem) -> some View {
        Group {
            if item.isImage, let nsImage = appState.history.loadImage(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500, maxHeight: 580)
                    .padding(12)
            } else {
                ScrollView {
                    Text(item.text)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .frame(idealWidth: 500, maxHeight: 600)
    }

    private var shortcutsHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                shortcutRow("Open Clipiary", appState.settings.globalShortcut.displayString)
                shortcutRow("Quick paste previous", appState.settings.quickPasteShortcut.displayString)
                shortcutRow("Focus search", "Cmd F")
                shortcutRow("Favorite or unfavorite", "Cmd D")
                shortcutRow("Move selection", "Up / Down")
                shortcutRow("Switch tabs", "Left / Right")
                shortcutRow("Restore selected item", "Return")
                shortcutRow("Preview selected item", "Space")
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
        switch appState.selectedTab.kind {
        case .history:
            return "Copy something, or enable copy-on-select to capture highlighted text."
        case .favorites(let name):
            return "Mark items as \(name) so they stay separate from the stream."
        }
    }

    private var emptyTitle: String {
        switch appState.selectedTab.kind {
        case .history:
            return "No clipboard history yet"
        case .favorites:
            return "No favorites yet"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(appState.allTabs) { tab in
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
        let count: Int
        switch tab.kind {
        case .history:
            count = appState.historyItems.count
        case .favorites(let name):
            count = appState.favoriteItems(for: name).count
        }

        return Button {
            appState.setSelectedTab(tab)
        } label: {
            HStack(spacing: 6) {
                Text(tab.displayName)
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

    @ViewBuilder
    private func favoriteButton(for item: HistoryItem) -> some View {
        if appState.configManager.favoriteTabs.count == 1 {
            Button {
                appState.selectedHistoryItemID = item.id
                let tabName = appState.configManager.favoriteTabs[0].name
                appState.toggleFavoriteTab(item, tabName: tabName)
                appState.ensureSelection()
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? Color.accentColor : .secondary)
            .opacity(hoveredItemID == item.id || item.isFavorite ? 1 : 0.55)
        } else {
            Button {
                appState.selectedHistoryItemID = item.id
                appState.toggleFavoriteSelectedItem()
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? Color.accentColor : .secondary)
            .opacity(hoveredItemID == item.id || item.isFavorite ? 1 : 0.55)
        }
    }

    private func favoriteTabPickerOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geometry in
            let overlayOrigin: CGPoint = {
                guard let anchor else {
                    return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                let rowRect = geometry[anchor]
                return CGPoint(
                    x: rowRect.midX,
                    y: rowRect.maxY
                )
            }()

            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        appState.showingFavoriteTabPicker = false
                    }

                favoriteTabPickerContent
                    .position(x: overlayOrigin.x, y: overlayOrigin.y)
            }
        }
    }

    private var favoriteTabPickerContent: some View {
        VStack(spacing: 2) {
            Text("Add to favorites")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            ForEach(Array(appState.configManager.favoriteTabs.enumerated()), id: \.element.id) { index, tabConfig in
                let isInTab = appState.selectedItem?.favoriteTabs.contains(tabConfig.name) ?? false
                let isFocused = index == appState.favoriteTabPickerIndex

                HStack(spacing: 6) {
                    Text(tabConfig.name)
                        .font(.system(size: 12))
                    Spacer()
                    if isInTab {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.favoriteTabPickerIndex = index
                    appState.confirmPickerSelection()
                }
            }

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: 6) {
                Image(systemName: appState.selectedItem?.isMonospace == true ? "checkmark.square" : "square")
                    .font(.system(size: 11))
                Text("Console font")
                    .font(.system(size: 11))
                Spacer()
                Text("M")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .foregroundStyle(appState.selectedItem?.isMonospace == true ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                appState.togglePickerMonospace()
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
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

    private func overrideScrollerStyle() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                for scrollView in window.contentView?.findAll(ofType: NSScrollView.self) ?? [] {
                    scrollView.scrollerStyle = .overlay
                }
            }
        }
    }
}

private extension NSView {
    func findAll<T: NSView>(ofType type: T.Type) -> [T] {
        var results: [T] = []
        if let match = self as? T { results.append(match) }
        for child in subviews { results.append(contentsOf: child.findAll(ofType: type)) }
        return results
    }
}
