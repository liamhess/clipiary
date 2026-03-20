import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private let appIconCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 100
    return cache
}()

@MainActor
private func appIcon(for bundleID: String?) -> NSImage? {
    guard let bundleID else { return nil }
    let key = bundleID as NSString
    if let cached = appIconCache.object(forKey: key) { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    appIconCache.setObject(icon, forKey: key)
    return icon
}

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
    @State private var draggingItemID: HistoryItem.ID?
    @State private var dropTargetIndex: Int?
    @State private var settingsExpanded = false
    @State private var shortcutsHelpPresented = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header
                historySection
                    .layoutPriority(settingsExpanded ? 0 : 1)
                settingsSection
                    .frame(maxHeight: settingsExpanded ? geometry.size.height * 0.6 : nil)
                    .layoutPriority(settingsExpanded ? 1 : 0)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .background(WindowDragArea())

            tabBar
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var historySection: some View {
        let items = appState.activeItems

        return VStack(alignment: .leading, spacing: 10) {
            searchField
                .frame(height: appState.settings.alwaysShowSearch || !appState.searchQuery.isEmpty ? nil : 0)
                .clipped()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if items.isEmpty {
                            emptyState
                        } else {
                            historyGroup(title: "", items: items)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .onAppear { overrideScrollerStyle() }
                .popover(
                    isPresented: Binding(
                        get: { appState.isPreviewVisible && appState.selectedItem != nil },
                        set: { if !$0 { appState.isPreviewVisible = false } }
                    ),
                    arrowEdge: .trailing
                ) {
                    if let item = appState.selectedItem {
                        itemPreview(for: item)
                    }
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
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
            }

            if settingsExpanded {
                ScrollView {
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
                        title: "Show app icons",
                        isOn: Binding(
                            get: { appState.settings.showAppIcons },
                            set: { appState.settings.showAppIcons = $0 }
                        )
                    )

                    settingsToggleRow(
                        title: "Always show search field",
                        isOn: Binding(
                            get: { appState.settings.alwaysShowSearch },
                            set: { appState.settings.alwaysShowSearch = $0 }
                        )
                    )

                    settingMetric(
                        title: "Paste count bar",
                        value: nil
                    ) {
                        Picker("", selection: Binding(
                            get: { appState.settings.pasteCountBarScheme },
                            set: { appState.settings.pasteCountBarScheme = $0 }
                        )) {
                            ForEach(PasteCountBarScheme.allSchemes, id: \.id) { scheme in
                                Text(scheme.label).tag(scheme.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

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
                shortcutsHelpPresented.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.circle")
                    Text("Keyboard Shortcuts")
                }
            }
            .help("Keyboard shortcuts")
            .popover(isPresented: $shortcutsHelpPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                shortcutsHelpPopover
            }
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
        let maxPasteCount = max(items.map(\.pasteCount).max() ?? 1, 1)
        let showAppIcons = appState.settings.showAppIcons
        let showItemDetails = appState.settings.showItemDetails
        let pasteCountBarScheme = appState.settings.pasteCountBarScheme
        let singleFavoriteTab = appState.configManager.favoriteTabs.count == 1
        let singleFavoriteTabName = singleFavoriteTab ? appState.configManager.favoriteTabs.first?.name : nil
        let selectedID = appState.selectedHistoryItemID
        let showingPicker = appState.showingFavoriteTabPicker
        let indexedItems = items.enumerated().map { ($0.offset, $0.element) }

        return LazyVStack(spacing: 2) {
            ForEach(indexedItems, id: \.1.id) { index, item in
                VStack(spacing: 0) {
                    if dropTargetIndex == index, draggingItemID != item.id {
                        dropIndicator
                    }
                    HistoryRowView(
                        item: item,
                        maxPasteCount: maxPasteCount,
                        isSelected: selectedID == item.id,
                        showAppIcons: showAppIcons,
                        showItemDetails: showItemDetails,
                        pasteCountBarScheme: pasteCountBarScheme,
                        singleFavoriteTab: singleFavoriteTab,
                        singleFavoriteTabName: singleFavoriteTabName,
                        showingFavoriteTabPicker: showingPicker && selectedID == item.id,
                        appState: appState
                    )
                    .opacity(draggingItemID == item.id ? 0.4 : 1.0)
                    .onDrag {
                        draggingItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.plainText], delegate: ReorderDropDelegate(
                        itemIndex: index,
                        draggingItemID: $draggingItemID,
                        dropTargetIndex: $dropTargetIndex,
                        onReorder: { appState.reorderItem($0, toIndex: $1) }
                    ))
                }
            }

            // Drop zone at the end of the list
            if draggingItemID != nil {
                Color.clear
                    .frame(height: 30)
                    .onDrop(of: [.plainText], delegate: ReorderDropDelegate(
                        itemIndex: items.count,
                        draggingItemID: $draggingItemID,
                        dropTargetIndex: $dropTargetIndex,
                        onReorder: { appState.reorderItem($0, toIndex: $1) }
                    ))
            }

            if let dropIndex = dropTargetIndex, dropIndex >= items.count, draggingItemID != nil {
                dropIndicator
            }
        }
    }

    private var dropIndicator: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
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
        .contextMenu {
            Button("Add New Tab...") {
                if let name = Self.showTextInputAlert(title: "Add New Tab", message: "Enter a name for the new tab:", defaultValue: "") {
                    appState.addFavoriteTab(name: name)
                }
            }

            if case .favorites(let name) = tab.kind {
                Button("Rename...") {
                    if let newName = Self.showTextInputAlert(title: "Rename Tab", message: "Enter a new name:", defaultValue: name) {
                        if newName != name {
                            appState.renameFavoriteTab(oldName: name, newName: newName)
                        }
                    }
                }

                let tabs = appState.configManager.favoriteTabs
                if let index = tabs.firstIndex(where: { $0.name == name }) {
                    Button("Move Left") {
                        appState.moveFavoriteTab(from: index, to: index - 1)
                    }
                    .disabled(index == 0)

                    Button("Move Right") {
                        appState.moveFavoriteTab(from: index, to: index + 1)
                    }
                    .disabled(index >= tabs.count - 1)
                }

                Divider()

                Button("Delete", role: .destructive) {
                    if Self.showDeleteConfirmAlert(tabName: name) {
                        appState.deleteFavoriteTab(name: name)
                    }
                }
            }
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

            Divider()
                .padding(.vertical, 2)

            if appState.isRecordingItemShortcut {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Press shortcut...")
                            .font(.system(size: 11))
                        Spacer()
                        Text("Esc")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    if let error = appState.itemShortcutError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    if let shortcut = appState.selectedItem?.globalShortcut {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11))
                        Text(shortcut.displayString)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Del")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        Text("S")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11))
                        Text("Set global shortcut")
                            .font(.system(size: 11))
                        Spacer()
                        Text("S")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                }
                .foregroundStyle(appState.selectedItem?.globalShortcut != nil ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.startRecordingItemShortcut()
                }
            }
        }
        .padding(10)
        .frame(width: 240)
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

    private static func showTextInputAlert(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let result = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func showDeleteConfirmAlert(tabName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(tabName)\"?"
        alert.informativeText = "Items in this tab will not be deleted, but they will lose their assignment to this tab."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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

private struct HistoryRowView: View {
    let item: HistoryItem
    let maxPasteCount: Int
    let isSelected: Bool
    let showAppIcons: Bool
    let showItemDetails: Bool
    let pasteCountBarScheme: String
    let singleFavoriteTab: Bool
    let singleFavoriteTabName: String?
    let showingFavoriteTabPicker: Bool
    let appState: AppState

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    appState.selectedHistoryItemID = item.id
                    appState.restore(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            if showAppIcons, let icon = appIcon(for: item.bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: item.isImage ? "photo" : item.source == .copyOnSelect ? "cursorarrow.rays" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(item.isImage ? Color.orange : item.source == .copyOnSelect ? Color.accentColor : .secondary)
                                    .frame(width: 16, height: 16, alignment: .center)
                            }
                            if showAppIcons, item.source == .copyOnSelect {
                                Image(systemName: "cursorarrow.rays")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .offset(x: 4, y: 4)
                            }
                        }

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

                HStack(spacing: 8) {
                    if let shortcut = item.globalShortcut {
                        Text(shortcut.displayString)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
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
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0.45)
                }
            }

            if showItemDetails {
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
            showingFavoriteTabPicker ? anchor : nil
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedHistoryItemID = item.id
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.accentColor.opacity(0.09)
        }
        return .clear
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
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < filled ? colors[index] : Color.secondary.opacity(0.15))
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
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? Color.accentColor : .secondary)
            .opacity(isHovered || item.isFavorite ? 1 : 0.55)
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
            .opacity(isHovered || item.isFavorite ? 1 : 0.55)
        }
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let itemIndex: Int
    @Binding var draggingItemID: HistoryItem.ID?
    @Binding var dropTargetIndex: Int?
    let onReorder: (HistoryItem.ID, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard draggingItemID != nil else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            dropTargetIndex = itemIndex
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == itemIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetIndex = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = draggingItemID else { return false }
        onReorder(id, itemIndex)
        draggingItemID = nil
        dropTargetIndex = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingItemID != nil
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

enum PasteCountBarScheme {
    struct Scheme {
        let id: String
        let label: String
        let colors: [Color]
    }

    static let allSchemes: [Scheme] = [
        Scheme(id: "none", label: "No bar", colors: []),
        Scheme(id: "neon", label: "Neon", colors: [
            Color(red: 0.40, green: 0.40, blue: 0.95),
            Color(red: 0.60, green: 0.30, blue: 0.85),
            Color(red: 0.90, green: 0.20, blue: 0.75),
            Color(red: 0.95, green: 0.35, blue: 0.55),
            Color(red: 0.95, green: 0.60, blue: 0.30),
        ]),
        Scheme(id: "ocean", label: "Ocean", colors: [
            Color(red: 0.10, green: 0.50, blue: 0.70),
            Color(red: 0.15, green: 0.60, blue: 0.75),
            Color(red: 0.20, green: 0.72, blue: 0.80),
            Color(red: 0.30, green: 0.82, blue: 0.82),
            Color(red: 0.45, green: 0.92, blue: 0.85),
        ]),
        Scheme(id: "sunset", label: "Sunset", colors: [
            Color(red: 0.95, green: 0.85, blue: 0.25),
            Color(red: 0.97, green: 0.65, blue: 0.20),
            Color(red: 0.95, green: 0.45, blue: 0.20),
            Color(red: 0.90, green: 0.25, blue: 0.25),
            Color(red: 0.70, green: 0.15, blue: 0.30),
        ]),
        Scheme(id: "forest", label: "Forest", colors: [
            Color(red: 0.20, green: 0.55, blue: 0.25),
            Color(red: 0.30, green: 0.65, blue: 0.30),
            Color(red: 0.45, green: 0.75, blue: 0.35),
            Color(red: 0.60, green: 0.82, blue: 0.40),
            Color(red: 0.78, green: 0.90, blue: 0.50),
        ]),
        Scheme(id: "ember", label: "Ember", colors: [
            Color(red: 0.55, green: 0.10, blue: 0.10),
            Color(red: 0.75, green: 0.18, blue: 0.10),
            Color(red: 0.90, green: 0.35, blue: 0.10),
            Color(red: 0.97, green: 0.55, blue: 0.15),
            Color(red: 1.00, green: 0.78, blue: 0.25),
        ]),
        Scheme(id: "aurora", label: "Aurora", colors: [
            Color(red: 0.10, green: 0.85, blue: 0.55),
            Color(red: 0.20, green: 0.70, blue: 0.75),
            Color(red: 0.35, green: 0.50, blue: 0.90),
            Color(red: 0.55, green: 0.35, blue: 0.90),
            Color(red: 0.75, green: 0.25, blue: 0.85),
        ]),
        Scheme(id: "monochrome", label: "Monochrome", colors: [
            Color(white: 0.40),
            Color(white: 0.50),
            Color(white: 0.60),
            Color(white: 0.72),
            Color(white: 0.85),
        ]),
        Scheme(id: "candy", label: "Candy", colors: [
            Color(red: 0.95, green: 0.40, blue: 0.60),
            Color(red: 0.85, green: 0.35, blue: 0.80),
            Color(red: 0.65, green: 0.40, blue: 0.95),
            Color(red: 0.45, green: 0.55, blue: 0.95),
            Color(red: 0.35, green: 0.80, blue: 0.95),
        ]),
    ]

    static func colors(for schemeID: String) -> [Color] {
        allSchemes.first { $0.id == schemeID }?.colors ?? allSchemes[1].colors
    }
}
