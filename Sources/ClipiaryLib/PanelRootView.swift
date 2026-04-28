import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @FocusState private var searchFocused: Bool
    @State private var draggingItemID: HistoryItem.ID?
    @State private var dropTargetIndex: Int?
    @State private var shortcutsHelpPresented = false
    @State private var snippetDescriptionText: String = ""
    @State private var searchFieldText: String = ""
    @State private var highlightTerms: [String] = []
    @State private var highlightDebounceTask: Task<Void, Never>?
    @FocusState private var isDescriptionFieldFocused: Bool
    @State private var itemEditText: String = ""
    @FocusState private var isItemTextEditorFocused: Bool
    @State private var separatorNameText: String = ""
    @FocusState private var isSeparatorNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: theme.spacing.sectionSpacing) {
            header
            historySection
            if UpdaterManager.shared.showOverlay {
                UpdatePanelView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.spacing.panelPadding)
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .blur(radius: appState.showingFavoriteTabPicker ? (theme.options.overlayBlurRadius ?? 0) : 0)
        .animation(.easeInOut(duration: 0.1), value: appState.showingFavoriteTabPicker)
        .background(panelBackground)
        .shadow(
            color: theme.resolvedPanelGlow?.color ?? .clear,
            radius: theme.resolvedPanelGlow?.radius ?? 0
        )
        .onChange(of: appState.searchFocusRequestID) {
            searchFocused = true
        }
        .onChange(of: appState.popoverOpenRequestID) {
            shortcutsHelpPresented = false
        }
        .animation(.easeInOut(duration: 0.1), value: UpdaterManager.shared.showOverlay)
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
        VStack(alignment: .leading, spacing: 10) {
            searchField
                .frame(height: appState.settings.alwaysShowSearch || !searchFieldText.isEmpty ? nil : 0)
                .clipped()

            ZStack {
                ForEach(appState.allTabs) { tab in
                    let items = appState.filteredItems(for: tab)
                    TabListView(tab: tab) {
                        if items.isEmpty {
                            emptyState
                        } else {
                            historyGroup(title: "", items: items)
                        }
                    }
                    .opacity(tab == appState.selectedTab ? 1 : 0)
                    .allowsHitTesting(tab == appState.selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                let cornerRadius = theme.cornerRadii.contentArea
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(panelFill)
                    if theme.fills.contentArea.texture != nil {
                        TextureOverlay(fill: theme.fills.contentArea, themesDirectory: appState.themeManager.themesDirectoryURL)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
            }
            .innerShadow(cornerRadius: theme.cornerRadii.contentArea, shadow: theme.resolvedContentAreaInnerShadow)
            .overlay {
                let border = theme.resolvedContentAreaBorder
                if border.isVisible {
                    RoundedRectangle(cornerRadius: theme.cornerRadii.contentArea, style: .continuous)
                        .stroke(border.color, style: border.strokeStyle)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            accessibilityStatus
            Spacer()
            Button {
                handleUpdateButtonPress()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: UpdaterManager.shared.updateAvailable ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                    Text(UpdaterManager.shared.updateAvailable ? "Update Available" : "Updates")
                }
            }
            .help(updateButtonHelpText)
            .disabled(updateButtonDisabled)
            Button {
                SettingsWindowController.shared.open()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
            }
            .help("Settings (⌘,)")
            Button {
                shortcutsHelpPresented.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.circle")
                    Text("Keyboard")
                }
            }
            .help("Keyboard shortcuts")
            .popover(isPresented: $shortcutsHelpPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                shortcutsHelpPopover
            }
            Button {
                if Self.showClearHistoryConfirmAlert() {
                    appState.history.clearNonFavorites()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
            }
            .help("Clear all History items (except favorites)")
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
        .foregroundStyle(theme.resolvedTextSecondary)
        .padding(.horizontal, 2)
    }

    private func handleUpdateButtonPress() {
        if UpdaterManager.shared.showOverlay {
            UpdaterManager.shared.dismissOverlay()
            return
        }
        #if DEBUG
        if !UpdaterManager.shared.isConfigured || NSEvent.modifierFlags.contains(.option) {
            UpdaterManager.shared.showDebugPreview()
            return
        }
        #endif
        UpdaterManager.shared.checkForUpdates()
    }

    private var updateButtonDisabled: Bool {
        #if DEBUG
        false
        #else
        !UpdaterManager.shared.isConfigured
        #endif
    }

    private var updateButtonHelpText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var text = "Check for Updates (v\(version))"
        if !UpdaterManager.shared.isConfigured {
            #if DEBUG
            text += " — debug preview available in this build"
            #else
            text += " — updates not available in this build"
            #endif
        }
        #if DEBUG
        text += " — hold Option while clicking to preview the changelog UI"
        #endif
        return text
    }

    private var accessibilityStatus: some View {
        HStack(spacing: 6) {
            let isTrusted = appState.permissionManager.isTrusted
            let hasInputMonitoring = appState.inputMonitoringPermissionManager.isTrusted
            let copyOnSelect = appState.settings.isCopyOnSelectEnabled
            let smartPaste = appState.settings.isCopyOnSelectSmartPasteEnabled
            let monitoring = appState.settings.isClipboardMonitoringEnabled
            let allDisabled = !monitoring && !copyOnSelect
            let copyOnSelectNeedsPermission = copyOnSelect && !isTrusted
            let smartPasteNeedsPermission = copyOnSelect && smartPaste && !hasInputMonitoring

            Circle()
                .fill(
                    allDisabled || copyOnSelectNeedsPermission || smartPasteNeedsPermission
                    ? theme.resolvedStatusWarning
                    : !isTrusted ? theme.resolvedStatusWarning : theme.resolvedStatusReady
                )
                .frame(width: 6, height: 6)
            if allDisabled {
                Text("Clipboard Monitoring Disabled")
                    .font(.system(size: 11, weight: .medium))
            } else if smartPasteNeedsPermission {
                Button("Input Monitoring Required") {
                    appState.requestInputMonitoringAccess()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .help("Input Monitoring is needed so smart paste can intercept Cmd+V before the target app pastes")
            } else if copyOnSelectNeedsPermission {
                Button("Accessibility Required") {
                    appState.refreshCopyOnSelectPermissions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .help("Accessibility permissions needed for copy-on-select and direct paste of history elements")
            } else if !isTrusted {
                Button("Accessibility Required") {
                    appState.refreshCopyOnSelectPermissions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .help("Accessibility permissions needed for direct paste of history elements")
            } else {
                Text(copyOnSelect ? "Copy-on-select ready" : "Clipboard Monitoring")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(theme.resolvedTextSecondary)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: Binding(
                get: { searchFieldText },
                set: { newValue in
                    searchFieldText = newValue
                    appState.searchQuery = newValue
                    scheduleHighlightUpdate(for: newValue)
                }
            ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(keys: [.upArrow, .downArrow]) { _ in .handled }
                .onKeyPress(.space) { searchFieldText.isEmpty ? .handled : .ignored }
                .onChange(of: appState.searchQuery) {
                    appState.ensureSelection()
                    // Sync back when searchQuery is cleared externally (e.g. paste actions)
                    if appState.searchQuery.isEmpty && !searchFieldText.isEmpty {
                        searchFieldText = ""
                        highlightDebounceTask?.cancel()
                        highlightTerms = []
                    }
                }
                .onChange(of: appState.popoverOpenRequestID) {
                    searchFieldText = ""
                    highlightDebounceTask?.cancel()
                    highlightTerms = []
                }
            if !searchFieldText.isEmpty {
                Button {
                    searchFieldText = ""
                    appState.searchQuery = ""
                    highlightDebounceTask?.cancel()
                    highlightTerms = []
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
            RoundedRectangle(cornerRadius: theme.cornerRadii.searchField, style: .continuous)
                .fill(panelFill)
        )
        .overlay {
            let border = theme.resolvedSearchFieldBorder
            if border.isVisible {
                RoundedRectangle(cornerRadius: theme.cornerRadii.searchField, style: .continuous)
                    .stroke(border.color, style: border.strokeStyle)
            }
        }
        .innerShadow(cornerRadius: theme.cornerRadii.searchField, shadow: theme.resolvedSearchFieldInnerShadow)
    }

    private func historyGroup(title: String, items: [HistoryItem]) -> some View {
        let maxPasteCount = max(items.map(\.pasteCount).max() ?? 1, 1)
        let showAppIcons = appState.settings.showAppIcons
        let showItemDetails = appState.settings.showItemDetails
        let showCharCountBadge = appState.settings.showCharCountBadge
        let sizeBarScheme = appState.settings.sizeBarScheme
        let sizeBarThresholds = appState.settings.parsedSizeBarThresholds
        let pasteCountBarScheme = appState.settings.pasteCountBarScheme
        let itemLineLimit = appState.settings.itemLineLimit
        let singleFavoriteTab = appState.configManager.favoriteTabs.count == 1
        let singleFavoriteTabName = singleFavoriteTab ? appState.configManager.favoriteTabs.first?.name : nil
        let selectedID = appState.selectedHistoryItemID
        let showingPicker = appState.showingFavoriteTabPicker
        let showFavoriteTabBadges = appState.settings.showFavoriteTabBadges && appState.selectedTab.kind == .history
        let searchTerms = highlightTerms

        return LazyVStack(spacing: theme.spacing.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    if dropTargetIndex == index, draggingItemID != item.id {
                        dropIndicator
                    }
                    Group {
                        if item.isSeparator {
                            separatorRow(for: item)
                        } else {
                            HistoryRowView(
                                item: item,
                                maxPasteCount: maxPasteCount,
                                isSelected: selectedID == item.id,
                                showAppIcons: showAppIcons,
                                showItemDetails: showItemDetails,
                                showCharCountBadge: showCharCountBadge,
                                sizeBarScheme: sizeBarScheme,
                                sizeBarThresholds: sizeBarThresholds,
                                pasteCountBarScheme: pasteCountBarScheme,
                                singleFavoriteTab: singleFavoriteTab,
                                singleFavoriteTabName: singleFavoriteTabName,
                                showingFavoriteTabPicker: showingPicker && selectedID == item.id,
                                favoriteTabNames: showFavoriteTabBadges ? item.favoriteTabs.sorted() : [],
                                itemLineLimit: itemLineLimit,
                                searchTerms: searchTerms,
                                appState: appState
                            )
                            .equatable()
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: RowHeightsKey.self, value: [geo.size.height])
                            })
                        }
                    }
                    .contextMenu {
                        if !item.isSeparator {
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
                        if case .favorites(let tabName) = appState.selectedTab.kind {
                            if !item.isSeparator {
                                Divider()
                                Button("Insert Separator Below") {
                                    appState.insertSeparator(after: item, inTab: tabName)
                                }
                            }
                            if item.isSeparator {
                                Button("Rename Separator") {
                                    appState.selectedHistoryItemID = item.id
                                    separatorNameText = item.text
                                    appState.isEditingSeparatorName = true
                                }
                                Button("Remove Separator", role: .destructive) {
                                    appState.removeSeparator(item)
                                }
                            }
                        }
                    }
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
            .fill(theme.resolvedAccent)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    private func separatorRow(for item: HistoryItem) -> some View {
        let glow = theme.resolvedSeparatorGlow
        let isEditing = appState.isEditingSeparatorName && appState.selectedHistoryItemID == item.id
        let isNamed = !item.text.isEmpty || isEditing

        return ZStack {
            if isNamed {
                if let glow {
                    RoundedRectangle(cornerRadius: theme.cornerRadii.separator, style: .continuous)
                        .fill(glow.color)
                        .blur(radius: glow.radius * 0.6)
                        .allowsHitTesting(false)
                }
                if let glow, let innerColor = glow.innerColor, let innerRadius = glow.innerRadius {
                    RoundedRectangle(cornerRadius: theme.cornerRadii.separator, style: .continuous)
                        .fill(innerColor)
                        .blur(radius: innerRadius * 0.5)
                        .allowsHitTesting(false)
                }
                RoundedRectangle(cornerRadius: theme.cornerRadii.separator, style: .continuous)
                    .fill(theme.resolvedSeparator)

                if isEditing {
                    TextField("Separator name", text: $separatorNameText)
                        .font(.system(size: 10, weight: .semibold))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($isSeparatorNameFieldFocused)
                        .onChange(of: isSeparatorNameFieldFocused) { _, focused in
                            if !focused, appState.isEditingSeparatorName { commitSeparatorName() }
                        }
                        .padding(.horizontal, 8)
                } else {
                    Text(item.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.resolvedSeparatorTextColor)
                }
            } else {
                let thickness = theme.resolvedSeparatorThickness
                if let glow {
                    Capsule()
                        .fill(glow.color)
                        .frame(height: thickness)
                        .blur(radius: glow.radius * 0.6)
                        .allowsHitTesting(false)
                }
                if let glow, let innerColor = glow.innerColor, let innerRadius = glow.innerRadius {
                    Capsule()
                        .fill(innerColor)
                        .frame(height: thickness)
                        .blur(radius: innerRadius * 0.5)
                        .allowsHitTesting(false)
                }
                Capsule()
                    .fill(theme.resolvedSeparator)
                    .frame(height: thickness)
            }
        }
        .frame(height: isNamed ? theme.spacing.separatorHeight : nil)
        .padding(.horizontal, theme.spacing.separatorInset)
        .padding(.vertical, isNamed ? 3 : 5)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard !isEditing else { return }
            appState.selectedHistoryItemID = item.id
            separatorNameText = item.text
            appState.isEditingSeparatorName = true
        })
        .onChange(of: appState.isEditingSeparatorName) { _, editing in
            if editing, appState.selectedHistoryItemID == item.id {
                separatorNameText = item.text
                DispatchQueue.main.async {
                    isSeparatorNameFieldFocused = true
                }
            }
        }
    }

    private func commitSeparatorName() {
        appState.setSeparatorName(separatorNameText)
        appState.isEditingSeparatorName = false
        appState.requestSearchFocus()
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

    private var shortcutsHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                shortcutRow("Open Clipiary", appState.settings.globalShortcut.displayString)
                shortcutRow("Quick paste previous", appState.settings.quickPasteShortcut.displayString)
                shortcutRow("Global alternate paste", appState.settings.globalAltPasteShortcut.displayString)
                shortcutRow("Settings", "⌘,")
                shortcutRow("Focus search", "⌘F")
                shortcutRow("Favorite or unfavorite", "⌘D")
                shortcutRow("Move selection", "↑ / ↓")
                shortcutRow("Switch tabs", "← / →")
                shortcutRow("Paste selected item", "Return")
                shortcutRow("Alternate paste format", appState.settings.localAltPasteShortcut.displayString)
                shortcutRow("Paste raw source (RTF/HTML)", appState.settings.localRawSourcePasteShortcut.displayString)
                shortcutRow("Paste as Markdown", appState.settings.localMarkdownPasteShortcut.displayString)
                shortcutRow("Context menu", appState.settings.localContextMenuShortcut.displayString)
                shortcutRow("Preview selected item", "Space")
                shortcutRow("Delete selected item", "⌫")
                shortcutRow("Reload theme", "⌃R")
                shortcutRow("Open Theme Builder", "⌃T")
                shortcutRow("Toggle perf logging", "⌃D")
                shortcutRow("Close popover", "Esc")
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder
    private var panelBackground: some View {
        let cornerRadius = theme.cornerRadii.panel
        ZStack {
            if theme.options.material != nil {
                // Material themes: the vibrancy material is the entire panel background.
                // fills.panel is not applied as a tint here — old saved themes carry a
                // fills.panel value that was the solid fallback for non-material mode,
                // and layering it would make the outer ring nearly opaque.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedMaterial)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.resolvedPanelFill)
            }
            if theme.fills.panel.texture != nil {
                TextureOverlay(fill: theme.fills.panel, themesDirectory: appState.themeManager.themesDirectoryURL)
            }
            if theme.options.animatedPanel {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let period = theme.options.animatedPanelPeriod ?? 8.0
                    let color = Color(hex: theme.options.animatedPanelColor) ?? theme.resolvedAccent
                    let t = timeline.date.timeIntervalSinceReferenceDate / period
                    let angle = t * .pi * 2
                    let start = UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 - 0.5 * sin(angle))
                    let end = UnitPoint(x: 0.5 - 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
                    LinearGradient(
                        colors: [color.opacity(0.0), color.opacity(0.22), color.opacity(0.0)],
                        startPoint: start,
                        endPoint: end
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            let border = theme.resolvedPanelBorder
            if border.isVisible {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border.color, style: border.strokeStyle)
            }
        }
    }

    private var resolvedMaterial: AnyShapeStyle {
        switch theme.options.material {
        case "ultraThin":   return AnyShapeStyle(.ultraThinMaterial)
        case "thin":        return AnyShapeStyle(.thinMaterial)
        case "regular":     return AnyShapeStyle(.regularMaterial)
        case "thick":       return AnyShapeStyle(.thickMaterial)
        case "ultraThick":  return AnyShapeStyle(.ultraThickMaterial)
        default:            return AnyShapeStyle(.regularMaterial)
        }
    }

    private var panelFill: AnyShapeStyle {
        // For material themes with no explicit contentArea color, use the same material
        // as the outer shell so the content area matches and the scroll view's own
        // system background doesn't show through. If contentArea has an explicit color
        // it is applied as a tint/overlay over the panel material.
        if theme.options.material != nil,
           theme.fills.contentArea.color == nil,
           theme.fills.contentArea.gradient == nil,
           theme.fills.contentArea.mesh == nil {
            return resolvedMaterial
        }
        return theme.resolvedContentAreaFill
    }

    private var emptyMessage: String {
        switch appState.selectedTab.kind {
        case .history:
            return "Copy something, or enable copy-on-select to capture highlighted text."
        case .favorites(let name):
            return "Mark items as \(name) so they stay separate from the stream."
        }
    }

    private func scheduleHighlightUpdate(for query: String) {
        highlightDebounceTask?.cancel()
        let terms = query
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else {
            highlightTerms = []
            return
        }
        highlightDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            highlightTerms = terms
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
        .background {
            let cornerRadius = theme.cornerRadii.tabBar
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.resolvedTabBarFill)
                if theme.fills.tabBar.texture != nil {
                    TextureOverlay(fill: theme.fills.tabBar, themesDirectory: appState.themeManager.themesDirectoryURL)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
        }
        .innerShadow(cornerRadius: theme.cornerRadii.tabBar, shadow: theme.resolvedTabBarInnerShadow)
        .overlay {
            let border = theme.resolvedTabBarBorder
            if border.isVisible {
                RoundedRectangle(cornerRadius: theme.cornerRadii.tabBar, style: .continuous)
                    .stroke(border.color, style: border.strokeStyle)
            }
        }
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
                    .foregroundStyle(isSelected ? theme.resolvedTextPrimary.opacity(0.7) : theme.resolvedTextSecondary)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                let cornerRadius = theme.cornerRadii.tabButton
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(theme.resolvedTabButtonSelectedFill)
                        if let selectedFill = theme.fills.tabButtonSelected, selectedFill.texture != nil {
                            TextureOverlay(fill: selectedFill, themesDirectory: appState.themeManager.themesDirectoryURL)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? theme.resolvedTextPrimary : theme.resolvedTextSecondary)
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
            let (leadingOffset, topOffset) = pickerOffset(anchor: anchor, geometry: geometry)
            ZStack(alignment: .topLeading) {
                ZStack {
                    Rectangle().fill(theme.resolvedOverlayFill)
                    if theme.fills.overlay.texture != nil {
                        TextureOverlay(fill: theme.fills.overlay, themesDirectory: appState.themeManager.themesDirectoryURL)
                    }
                }
                .ignoresSafeArea()
                .onTapGesture {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        appState.showingFavoriteTabPicker = false
                        appState.requestSearchFocus()
                    }

                favoriteTabPickerContent
                    .offset(x: leadingOffset, y: topOffset)
            }
        }
    }

    private func pickerOffset(anchor: Anchor<CGRect>?, geometry: GeometryProxy) -> (CGFloat, CGFloat) {
        let pickerWidth: CGFloat = 240
        let panelWidth = geometry.size.width
        let originX: CGFloat
        let originY: CGFloat
        if let anchor {
            let rowRect = geometry[anchor]
            originX = rowRect.midX
            originY = rowRect.maxY + 4
        } else {
            originX = panelWidth / 2
            originY = geometry.size.height / 2
        }
        let clampedX = min(max(originX, pickerWidth / 2 + 8), panelWidth - pickerWidth / 2 - 8)
        return (clampedX - pickerWidth / 2, originY)
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
                    RoundedRectangle(cornerRadius: theme.cornerRadii.pickerRow, style: .continuous)
                        .fill(isFocused ? AnyShapeStyle(theme.resolvedAccent.opacity(0.3)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.favoriteTabPickerIndex = index
                    appState.confirmPickerSelection()
                }
            }

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Edit text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isItemTextEditorFocused {
                        Text("E")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                    .fill(theme.resolvedPillBackground)
                            )
                    }
                }
                TextEditor(text: $itemEditText)
                    .font(.system(size: 11))
                    .focused($isItemTextEditorFocused)
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onChange(of: isItemTextEditorFocused) { _, focused in
                        appState.isEditingItemText = focused
                        if !focused {
                            appState.setItemText(itemEditText)
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: 6) {
                TextField("Description (optional)", text: $snippetDescriptionText)
                    .font(.system(size: 11))
                    .textFieldStyle(.roundedBorder)
                    .focused($isDescriptionFieldFocused)
                    .onChange(of: snippetDescriptionText) { _, newValue in
                        appState.setSnippetDescription(newValue)
                    }
                    .onChange(of: isDescriptionFieldFocused) { _, focused in
                        appState.isEditingSnippetDescription = focused
                    }
                    .onSubmit {
                        isDescriptionFieldFocused = false
                    }
                if !isDescriptionFieldFocused {
                    Text("D")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: theme.cornerRadii.keyBadge, style: .continuous)
                                .fill(theme.resolvedPillBackground)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

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
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadii.card, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadii.card, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            snippetDescriptionText = appState.selectedItem?.snippetDescription ?? ""
            itemEditText = appState.selectedItem?.text ?? ""
        }
        .onChange(of: appState.isEditingSnippetDescription) { _, editing in
            isDescriptionFieldFocused = editing
        }
        .onChange(of: appState.isEditingItemText) { _, editing in
            isItemTextEditorFocused = editing
        }
        .onChange(of: appState.showingFavoriteTabPicker) { _, showing in
            if !showing {
                isDescriptionFieldFocused = false
                isItemTextEditorFocused = false
            }
        }
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
                        .fill(theme.resolvedShortcutKeyBackground)
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

    private static func showClearHistoryConfirmAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Clear History?"
        alert.informativeText = "This will remove all history items except favorites. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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

}

private struct TabListView<Content: View>: View {
    let tab: AppState.PopoverTab
    @ViewBuilder let content: () -> Content
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @State private var selectedRowRect: CGRect = .zero
    @State private var scrollViewHeight: CGFloat = 0
    @State private var renderedRowHeights: [CGFloat] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    content()
                }
                .padding(theme.spacing.contentAreaPadding)
            }
            .scrollIndicators(.hidden)
            .onAppear { overrideScrollerStyle() }
            .coordinateSpace(name: "scrollArea")
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewHeight = geo.size.height; updatePageSize() }
                        .onChange(of: geo.size.height) { scrollViewHeight = $1; updatePageSize() }
                }
            }
            .onPreferenceChange(SelectedRowRectKey.self) { rect in
                selectedRowRect = rect
                updatePageSize()
            }
            .onPreferenceChange(RowHeightsKey.self) { heights in
                renderedRowHeights = heights
                updatePageSize()
            }
            .onChange(of: appState.selectedHistoryItemID) { oldID, newID in
                guard tab == appState.selectedTab else { return }
                guard let newID else { return }
                let items = appState.activeItems
                guard let newIdx = items.firstIndex(where: { $0.id == newID }) else { return }
                let oldIdx = oldID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
                let isTabSwitch = oldID != nil && oldIdx == nil

                DispatchQueue.main.async {
                    let rect = selectedRowRect
                    if isTabSwitch {
                        if rect != .zero && rect.minY >= 0 && rect.maxY <= scrollViewHeight { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                        return
                    }
                    let movingDown = oldIdx.map { newIdx >= $0 } ?? false
                    let anchor: UnitPoint
                    if rect == .zero {
                        anchor = movingDown ? .bottom : .top
                    } else if rect.maxY > scrollViewHeight {
                        anchor = .bottom
                    } else if rect.minY < 0 {
                        anchor = .top
                    } else {
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newID, anchor: anchor)
                    }
                }
            }
            .overlay {
                if tab == appState.selectedTab, appState.isPreviewVisible, let item = appState.selectedItem {
                    Color.clear
                        .popover(
                            isPresented: .constant(true),
                            attachmentAnchor: .rect(.rect(selectedRowRect)),
                            arrowEdge: .trailing
                        ) {
                            itemPreview(for: item)
                        }
                        .id(item.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transformPreference(SelectedRowAnchorKey.self) { value in
            if tab != appState.selectedTab { value = nil }
        }
    }

    private func updatePageSize() {
        let rowHeight: CGFloat
        if renderedRowHeights.isEmpty {
            rowHeight = selectedRowRect.height
        } else {
            rowHeight = renderedRowHeights.reduce(0, +) / CGFloat(renderedRowHeights.count)
        }
        guard rowHeight > 0, scrollViewHeight > 0 else { return }
        let rowSpacing = theme.spacing.rowSpacing
        let contentPadding = theme.spacing.contentAreaPadding
        let usable = scrollViewHeight - 2 * contentPadding + rowSpacing
        appState.visiblePageSize = max(1, Int(usable / (rowHeight + rowSpacing)))
    }

    private func itemPreview(for item: HistoryItem) -> some View {
        VStack(spacing: 0) {
            Group {
                if item.isImage, let nsImage = appState.history.loadImage(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500, maxHeight: 580)
                        .padding(12)
                } else {
                    ScrollView {
                        let previewLimit = 10_000
                        let truncated = item.textCount > previewLimit
                        let previewText = truncated ? String(item.text.prefix(previewLimit)) : item.text
                        VStack(alignment: .leading, spacing: 6) {
                            Text(previewText)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if truncated {
                                Text("Preview truncated at 10k characters")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            if let desc = item.snippetDescription {
                Divider()
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            Divider()
            HStack(spacing: 5) {
                if let icon = appIcon(for: item.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                        .opacity(0.6)
                }
                Text(item.appName)
                Text("·").foregroundStyle(.quaternary)
                Text(item.isImage ? "Image" : item.rtfData != nil ? "RTF" : item.htmlData != nil ? "HTML" : "Plain text")
                Text("·").foregroundStyle(.quaternary)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if !item.isImage {
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(item.textCount.compactCharCount) chars")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.15))
        }
        .frame(idealWidth: 500, maxHeight: 600)
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

// MARK: - Texture Overlay

struct TextureOverlay: View {
    let fill: ThemeFill
    let themesDirectory: URL
    @State private var displayImage: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let displayImage {
                    Image(nsImage: displayImage)
                        .resizable(resizingMode: .tile)
                        .opacity(fill.textureOpacity ?? 1.0)
                        .blendMode(fill.resolvedBlendMode)
                }
            }
            .task(id: loadKey) { load() }
    }

    private var loadKey: String { "\(fill.texture ?? "")@\(fill.textureScale ?? 1.0)" }

    private func load() {
        guard let ref = fill.texture, !ref.isEmpty else { displayImage = nil; return }
        if ref.hasPrefix("file:") {
            let filename = String(ref.dropFirst(5))
            guard let original = NSImage(contentsOf: themesDirectory.appending(path: filename)) else {
                displayImage = nil
                return
            }
            let scale = fill.textureScale ?? 1.0
            displayImage = scale == 1.0 ? original : scaled(original, by: scale)
        } else {
            displayImage = nil
        }
    }

    private func scaled(_ image: NSImage, by factor: Double) -> NSImage {
        let newSize = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }
}

// MARK: - Inner Shadow

extension View {
    /// Overlays an inner shadow (recessed-well effect) on a rounded rectangle.
    /// Draws a thick blurred stroke clipped to the shape bounds.
    /// Pass `shadow: nil` to skip the effect entirely.
    @ViewBuilder
    func innerShadow(cornerRadius: CGFloat, shadow: Theme.ResolvedInnerShadow?) -> some View {
        if let shadow {
            self.overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(shadow.color, lineWidth: (shadow.radius * 2) + 2)
                    .blur(radius: shadow.radius)
                    .offset(x: shadow.x, y: shadow.y)
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }
}
