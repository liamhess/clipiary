import AppKit
import SwiftUI

// MARK: - Editor State

@MainActor
@Observable
final class ThemeEditorState {
    var theme: Theme
    let isBuiltIn: Bool
    var showingDuplicatePopover = false
    var duplicateName = ""
    var showingDeleteAlert = false
    var showingRevertAlert = false
    private let snapshot: Theme?

    var isDirty: Bool { !isBuiltIn && theme != snapshot }

    init(theme: Theme) {
        self.theme = theme
        let builtIn = Theme.builtInThemes.contains(where: { $0.id == theme.id })
        self.isBuiltIn = builtIn
        self.duplicateName = "\(theme.name) Copy"
        self.snapshot = builtIn ? nil : theme
    }

    func revert() {
        guard let snapshot else { return }
        theme = snapshot
    }
}

// MARK: - Window Controller

/// NSHostingView subclass that bypasses SwiftUI's performKeyEquivalent for standard
/// text-editing shortcuts (Cmd+A/C/V/X/Z/Y), sending them directly to the first
/// responder so they reach the focused field editor inside text fields.
@MainActor
private final class ThemeBuilderHostingView: NSHostingView<AnyView> {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let selector: Selector? = switch chars {
        case "a": #selector(NSText.selectAll(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "x": #selector(NSText.cut(_:))
        case "z": #selector(UndoManager.undo)
        case "y": #selector(UndoManager.redo)
        default: nil
        }
        if let selector, let responder = window?.firstResponder, responder.responds(to: selector) {
            responder.perform(selector, with: nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class ThemeBuilderWindowController {
    static let shared = ThemeBuilderWindowController()

    private var window: NSWindow?
    private var colorPanelKVO: NSKeyValueObservation?
    private var fontPanelKVO: NSKeyValueObservation?

    init() {
        colorPanelKVO = NSColorPanel.shared.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            let isNowVisible = change.newValue == true
            Task { @MainActor [weak self] in
                guard let self, let win = self.window, self.isVisible else { return }
                if isNowVisible {
                    if NSColorPanel.shared.parent == nil {
                        win.addChildWindow(NSColorPanel.shared, ordered: .above)
                    }
                    NSColorPanel.shared.makeKeyAndOrderFront(nil)
                } else {
                    win.removeChildWindow(NSColorPanel.shared)
                }
            }
        }
        fontPanelKVO = NSFontPanel.shared.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            let isNowVisible = change.newValue == true
            Task { @MainActor [weak self] in
                guard let self, let win = self.window, self.isVisible else { return }
                if isNowVisible {
                    if NSFontPanel.shared.parent == nil {
                        win.addChildWindow(NSFontPanel.shared, ordered: .above)
                    }
                    NSFontPanel.shared.makeKeyAndOrderFront(nil)
                } else {
                    win.removeChildWindow(NSFontPanel.shared)
                }
            }
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect? { window?.frame }

    func orderFront(adjacentTo panelFrame: NSRect? = nil) {
        guard let window else { return }
        if let anchor = panelFrame, let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) }) {
            window.setFrameOrigin(bestOrigin(for: window.frame.size, adjacentTo: anchor, on: screen.visibleFrame))
        }
        window.makeKeyAndOrderFront(nil)
    }

    func open(themeID: String, appState: AppState, adjacentTo panelFrame: NSRect? = nil) {
        let theme = appState.themeManager.availableThemes.first { $0.id == themeID } ?? .default
        let state = ThemeEditorState(theme: theme)

        let rootView = ThemeBuilderView(editorState: state, appState: appState)
            .environment(\.theme, appState.themeManager.activeTheme)
            .preferredColorScheme(appState.themeManager.activeTheme.colorScheme)
            .environment(appState)

        if let existing = window, existing.isVisible {
            // Replace hosted view with new theme
            (existing.contentView as? NSHostingView<AnyView>)?.rootView = AnyView(rootView)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = ThemeBuilderHostingView(rootView: AnyView(rootView))
        let height = panelFrame.map { $0.height } ?? appState.settings.panelHeight
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Theme Builder"
        panel.contentView = hosting
        panel.minSize = NSSize(width: 560, height: 400)
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

        if let anchor = panelFrame, let screen = NSScreen.main {
            panel.setFrameOrigin(
                bestOrigin(for: panel.frame.size, adjacentTo: anchor, on: screen.visibleFrame)
            )
        } else {
            panel.center()
        }

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// Place the builder to the right of `anchor` if it fits; otherwise to the left.
    /// Vertically align the top edges. Clamp to the screen's visible frame.
    private func bestOrigin(for size: NSSize, adjacentTo anchor: NSRect, on screen: NSRect) -> NSPoint {
        let gap: CGFloat = 8
        var x: CGFloat
        if anchor.maxX + gap + size.width <= screen.maxX {
            x = anchor.maxX + gap                  // right of panel
        } else if anchor.minX - gap - size.width >= screen.minX {
            x = anchor.minX - gap - size.width     // left of panel
        } else {
            x = screen.maxX - size.width - gap     // fallback: flush right of screen
        }
        // Align top edges, then clamp vertically so window stays on screen
        var y = anchor.maxY - size.height
        y = max(screen.minY, min(y, screen.maxY - size.height))
        x = max(screen.minX, min(x, screen.maxX - size.width))
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Main Builder View

private enum BuilderSection: String, CaseIterable, Identifiable {
    case options = "Options"
    case fills = "Fills"
    case colors = "Colors"
    case borders = "Borders"
    case effects = "Effects"
    case cornerRadii = "Corner radii"
    case spacing = "Spacing"
    case fonts = "Fonts"

    var id: Self { self }

    var icon: String {
        switch self {
        case .options:     return "gearshape"
        case .fills:       return "drop.fill"
        case .colors:      return "paintpalette"
        case .borders:     return "square.dashed"
        case .effects:     return "sparkles"
        case .cornerRadii: return "app"
        case .spacing:     return "ruler"
        case .fonts:       return "textformat"
        }
    }
}

struct ThemeBuilderView: View {
    @State var editorState: ThemeEditorState
    let appState: AppState
    @State private var selectedSection: BuilderSection = .options
    @State private var sidebarTableView: NSTableView? = nil
    @State private var saveTask: Task<Void, Never>? = nil

    @Environment(\.theme) private var activeTheme

    var body: some View {
        VStack(spacing: 0) {
            // Header: theme picker + rename/hint
            headerRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            HStack(spacing: 0) {
                // Sidebar
                // Sidebar
                List(BuilderSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.system(size: 12))
                        .tag(section)
                }
                .listStyle(.sidebar)
                .onAppear { findAndStoreSidebarTableView() }
                .frame(width: 140)

                Divider()

                // Content
                ScrollView {
                    VStack(spacing: 14) {
                        sectionContent(selectedSection)
                    }
                    .padding(16)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DispatchQueue.main.async {
                        guard let window = NSApp.keyWindow else { return }
                        // If a text field is now focused, leave it alone; otherwise keep sidebar active
                        if !(window.firstResponder is NSText) {
                            window.makeFirstResponder(sidebarTableView)
                        }
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            switch activeTheme.options.material {
            case "ultraThin":  Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            case "thin":       Rectangle().fill(.thinMaterial).ignoresSafeArea()
            case "regular":    Rectangle().fill(.regularMaterial).ignoresSafeArea()
            case "thick":      Rectangle().fill(.thickMaterial).ignoresSafeArea()
            case "ultraThick": Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            default:           Rectangle().fill(activeTheme.resolvedPanelFill).ignoresSafeArea()
            }
        }
        .onChange(of: editorState.theme) {
            guard !editorState.isBuiltIn else { return }
            saveTask?.cancel()
            let theme = editorState.theme
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                try? appState.themeManager.save(theme)
            }
        }
        .background(ThemeBuilderScrollConfigurator())
    }

    @ViewBuilder
    private func sectionContent(_ section: BuilderSection) -> some View {
        switch section {
        case .options:     optionsSection
        case .fills:       fillsSection
        case .colors:      colorsSection
        case .borders:     bordersSection
        case .effects:     effectsSection
        case .cornerRadii: cornerRadiiSection
        case .spacing:     spacingSection
        case .fonts:       fontsSection
        }
    }

    private func findAndStoreSidebarTableView() {
        DispatchQueue.main.async {
            guard let root = NSApp.keyWindow?.contentView else { return }
            func findTableView(_ view: NSView) -> NSTableView? {
                if let tv = view as? NSTableView { return tv }
                for sub in view.subviews { if let found = findTableView(sub) { return found } }
                return nil
            }
            if let tv = findTableView(root) {
                sidebarTableView = tv
                NSApp.keyWindow?.makeFirstResponder(tv)
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Theme selector — switches the builder to any available theme
            Picker("", selection: Binding(
                get: { editorState.theme.id },
                set: { id in
                    guard id != editorState.theme.id else { return }
                    if let theme = appState.themeManager.availableThemes.first(where: { $0.id == id }) {
                        appState.settings.selectedThemeID = id
                        editorState = ThemeEditorState(theme: theme)
                    }
                }
            )) {
                let builtInIDs = Set(Theme.builtInThemes.map { $0.id })
                let builtIns = appState.themeManager.availableThemes.filter { builtInIDs.contains($0.id) }
                let custom = appState.themeManager.availableThemes.filter { !builtInIDs.contains($0.id) }
                if !builtIns.isEmpty {
                    Section("Built-in") {
                        ForEach(builtIns, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
                if !custom.isEmpty {
                    Section("Custom") {
                        ForEach(custom, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .semibold))

            if editorState.isBuiltIn {
                // Built-in hint — inline, where the rename field would be
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Built-in — duplicate to edit")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            } else {
                // Rename field — only for custom themes
                Text("Name:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                TextField("Theme name", text: $editorState.theme.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            duplicateButton

            if editorState.isDirty {
                Button {
                    editorState.showingRevertAlert = true
                } label: {
                    Text("Revert")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .alert("Revert \"\(editorState.theme.name)\"?", isPresented: $editorState.showingRevertAlert) {
                    Button("Revert", role: .destructive) {
                        editorState.revert()
                        try? appState.themeManager.save(editorState.theme)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All changes will be discarded and the theme will be restored to the state it was in when you opened the builder.")
                }
            }

            if !editorState.isBuiltIn {
                Button(role: .destructive) {
                    editorState.showingDeleteAlert = true
                } label: {
                    Text("Delete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .alert("Delete \"\(editorState.theme.name)\"?", isPresented: $editorState.showingDeleteAlert) {
                    Button("Delete", role: .destructive) {
                        try? appState.themeManager.delete(id: editorState.theme.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This theme will be permanently removed.")
                }
            }

            Button {
                NSWorkspace.shared.open(appState.themeManager.themesDirectoryURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open themes folder in Finder")
        }
    }

    private var duplicateButton: some View {
        Button {
            editorState.duplicateName = "\(editorState.theme.name) Copy"
            editorState.showingDuplicatePopover = true
        } label: {
            Text("Duplicate")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $editorState.showingDuplicatePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New theme name")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Name", text: $editorState.duplicateName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 220)
                    .onSubmit {
                        let name = editorState.duplicateName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        if let copy = try? appState.themeManager.duplicate(editorState.theme, newName: name) {
                            appState.settings.selectedThemeID = copy.id
                            editorState = ThemeEditorState(theme: copy)
                        }
                        editorState.showingDuplicatePopover = false
                    }
                HStack {
                    Spacer()
                    Button("Cancel") { editorState.showingDuplicatePopover = false }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    Button("Duplicate") {
                        let name = editorState.duplicateName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        if let copy = try? appState.themeManager.duplicate(editorState.theme, newName: name) {
                            appState.settings.selectedThemeID = copy.id
                            editorState = ThemeEditorState(theme: copy)
                        }
                        editorState.showingDuplicatePopover = false
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 11))
                    .disabled(editorState.duplicateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        builderCard("Options") {
            let disabled = editorState.isBuiltIn

            builderRow("Appearance") {
                Picker("", selection: $editorState.theme.options.appearance) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(disabled)
            }
            builderRow("Material background") {
                Picker("", selection: Binding(
                    get: { editorState.theme.options.material ?? "none" },
                    set: { editorState.theme.options.material = $0 == "none" ? nil : $0 }
                )) {
                    Text("None").tag("none")
                    Text("Ultra Thin").tag("ultraThin")
                    Text("Thin").tag("thin")
                    Text("Regular").tag("regular")
                    Text("Thick").tag("thick")
                    Text("Ultra Thick").tag("ultraThick")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(disabled)
            }
            builderToggle("Use system accent color", isOn: $editorState.theme.options.useSystemAccent, disabled: disabled)
            builderToggle("Animated panel border", isOn: $editorState.theme.options.animatedPanel, disabled: disabled)

            DependentGroup(enabled: editorState.theme.options.animatedPanel) {
                OptionalColorRow(
                    label: "Panel animation color",
                    hex: $editorState.theme.options.animatedPanelColor,
                    disabled: disabled
                )
                OptionalDoubleRow(
                    label: "Animation period (s)",
                    value: $editorState.theme.options.animatedPanelPeriod,
                    range: 0.5...20,
                    step: 0.5,
                    disabled: disabled
                )
            }

            OptionalDoubleRow(
                label: "Overlay blur radius",
                value: $editorState.theme.options.overlayBlurRadius,
                range: 1...20,
                step: 1,
                disabled: disabled
            )
        }
    }

    // MARK: - Fills Section

    private var fillsSection: some View {
        builderCard("Fills") {
            let disabled = editorState.isBuiltIn
            let d = Theme.Fills.default
            let accentHex = editorState.theme.resolvedAccent.hexString
            let hasMaterial = editorState.theme.options.material != nil
            FillEditorRow(label: "Panel", fill: $editorState.theme.fills.panel, disabled: disabled || hasMaterial, defaultFill: d.panel)
            if hasMaterial {
                Text("Panel fill is replaced by the material background. Set Material to None in Options to use a solid fill.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            FillEditorRow(label: "Content area", fill: $editorState.theme.fills.contentArea, disabled: disabled, defaultFill: d.contentArea)
            FillEditorRow(label: "Tab bar", fill: $editorState.theme.fills.tabBar, disabled: disabled, defaultFill: d.tabBar)
            OptionalFillEditorRow(label: "Tab button selected", fill: $editorState.theme.fills.tabButtonSelected, disabled: disabled, defaultValue: d.tabButtonSelected)
            FillEditorRow(label: "Selected row", fill: $editorState.theme.fills.rowSelected, disabled: disabled, defaultFill: d.rowSelected, accentHex: accentHex)
            FillEditorRow(label: "Hovered row", fill: $editorState.theme.fills.rowHovered, disabled: disabled, defaultFill: d.rowHovered, accentHex: accentHex)
            FillEditorRow(label: "Card", fill: $editorState.theme.fills.card, disabled: disabled, defaultFill: d.card)
            FillEditorRow(label: "Overlay", fill: $editorState.theme.fills.overlay, disabled: disabled, defaultFill: d.overlay)
        }
    }

    // MARK: - Colors Section

    private var colorsSection: some View {
        builderCard("Colors") {
            let disabled = editorState.isBuiltIn
            let t = editorState.theme
            OptionalColorRow(label: "Accent", hex: $editorState.theme.colors.accent,
                             disabled: disabled, defaultColor: .accentColor, defaultLabel: "system accent")

            builderSubHeader("Backgrounds")
            OptionalColorOpacityRow(label: "Pill background",
                                    hex: $editorState.theme.colors.pillBackground,
                                    opacity: $editorState.theme.colors.pillBackgroundOpacity,
                                    defaultOpacity: 0.12, disabled: disabled,
                                    defaultColor: .secondary, defaultLabel: "secondary @ 12%")
            OptionalColorOpacityRow(label: "Shortcut key background",
                                    hex: $editorState.theme.colors.shortcutKeyBackground,
                                    opacity: $editorState.theme.colors.shortcutKeyBackgroundOpacity,
                                    defaultOpacity: 0.06, disabled: disabled,
                                    defaultColor: .black, defaultLabel: "black @ 6%")
            OptionalColorOpacityRow(label: "Card stroke",
                                    hex: $editorState.theme.colors.cardStroke,
                                    opacity: $editorState.theme.colors.cardStrokeOpacity,
                                    defaultOpacity: 0.08, disabled: disabled,
                                    defaultColor: .white, defaultLabel: "white @ 8%")

            builderSubHeader("Text")
            OptionalColorRow(label: "Primary text", hex: $editorState.theme.colors.textPrimary,
                             disabled: disabled, defaultColor: .primary, defaultLabel: "system primary")
            OptionalColorRow(label: "Secondary text", hex: $editorState.theme.colors.textSecondary,
                             disabled: disabled, defaultColor: .secondary, defaultLabel: "system secondary")
            OptionalColorRow(label: "Tertiary text", hex: $editorState.theme.colors.textTertiary,
                             disabled: disabled, defaultColor: Color(nsColor: .tertiaryLabelColor), defaultLabel: "system tertiary")

            builderSubHeader("Indicators")
            OptionalColorRow(label: "Image indicator", hex: $editorState.theme.colors.imageIndicator,
                             disabled: disabled, defaultColor: .orange, defaultLabel: "orange")
            OptionalColorRow(label: "Status ready", hex: $editorState.theme.colors.statusReady,
                             disabled: disabled, defaultColor: Color(nsColor: .systemGreen), defaultLabel: "system green")
            OptionalColorRow(label: "Status warning", hex: $editorState.theme.colors.statusWarning,
                             disabled: disabled, defaultColor: Color(nsColor: .systemOrange), defaultLabel: "system orange")

            builderSubHeader("Search & gauge")
            OptionalColorRow(label: "Search highlight", hex: $editorState.theme.colors.searchHighlight,
                             disabled: disabled, defaultColor: t.resolvedAccent, defaultLabel: "accent color")
            OptionalColorOpacityRow(label: "Search highlight background",
                                    hex: $editorState.theme.colors.searchHighlightBackground,
                                    opacity: $editorState.theme.colors.searchHighlightBackgroundOpacity,
                                    defaultOpacity: 0.15, disabled: disabled,
                                    defaultColor: t.resolvedAccent, defaultLabel: "accent @ 15%")
            OptionalColorOpacityRow(label: "Gauge unfilled",
                                    hex: $editorState.theme.colors.gaugeUnfilled,
                                    opacity: $editorState.theme.colors.gaugeUnfilledOpacity,
                                    defaultOpacity: 0.15, disabled: disabled,
                                    defaultColor: .secondary, defaultLabel: "secondary @ 15%")
            OptionalColorOpacityRow(label: "Separator",
                                    hex: $editorState.theme.colors.separator,
                                    opacity: $editorState.theme.colors.separatorOpacity,
                                    defaultOpacity: 0.35, disabled: disabled,
                                    defaultColor: t.resolvedCardStroke, defaultLabel: "card stroke @ 35%")
        }
    }

    // MARK: - Borders Section

    private var bordersSection: some View {
        builderCard("Borders") {
            let disabled = editorState.isBuiltIn
            BorderEditorRow(label: "Panel", border: $editorState.theme.borders.panel, disabled: disabled)
            BorderEditorRow(label: "Content area", border: $editorState.theme.borders.contentArea, disabled: disabled)
            BorderEditorRow(label: "Selected row", border: $editorState.theme.borders.selectedRow, disabled: disabled)
            BorderEditorRow(label: "Card", border: $editorState.theme.borders.card, disabled: disabled)
            BorderEditorRow(label: "Search field", border: $editorState.theme.borders.searchField, disabled: disabled)
            BorderEditorRow(label: "Tab bar", border: $editorState.theme.borders.tabBar, disabled: disabled)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        builderCard("Effects / Glows") {
            let disabled = editorState.isBuiltIn
            GlowEditorRow(label: "Selected row glow", glow: $editorState.theme.effects.selectedRowGlow, disabled: disabled)
            GlowEditorRow(label: "Hovered row glow", glow: $editorState.theme.effects.hoveredRowGlow, disabled: disabled)
            GlowEditorRow(label: "Panel glow", glow: $editorState.theme.effects.panelGlow, disabled: disabled)
            GlowEditorRow(label: "Selected row text glow", glow: $editorState.theme.effects.selectedRowTextGlow, disabled: disabled)
            GlowEditorRow(label: "Hovered row text glow", glow: $editorState.theme.effects.hoveredRowTextGlow, disabled: disabled)
            GlowEditorRow(label: "Search highlight text glow", glow: $editorState.theme.effects.searchHighlightTextGlow, disabled: disabled)
            GlowEditorRow(label: "Separator glow", glow: $editorState.theme.effects.separatorGlow, disabled: disabled)
            builderSubHeader("Inner Shadows")
            InnerShadowEditorRow(label: "Tab bar inner shadow", shadow: $editorState.theme.effects.tabBarInnerShadow, disabled: disabled)
            InnerShadowEditorRow(label: "Content area inner shadow", shadow: $editorState.theme.effects.contentAreaInnerShadow, disabled: disabled)
        }
    }

    private var cornerRadiiSection: some View {
        builderCard("Corner Radii") {
            let disabled = editorState.isBuiltIn
            let d = Theme.CornerRadii.default
            RadiusRow(label: "Panel", value: $editorState.theme.cornerRadii.panel, defaultValue: d.panel, disabled: disabled)
            RadiusRow(label: "Content area", value: $editorState.theme.cornerRadii.contentArea, defaultValue: d.contentArea, disabled: disabled)
            RadiusRow(label: "Card", value: $editorState.theme.cornerRadii.card, defaultValue: d.card, disabled: disabled)
            RadiusRow(label: "Tab bar", value: $editorState.theme.cornerRadii.tabBar, defaultValue: d.tabBar, disabled: disabled)
            RadiusRow(label: "Row", value: $editorState.theme.cornerRadii.row, defaultValue: d.row, disabled: disabled)
            RadiusRow(label: "Search field", value: $editorState.theme.cornerRadii.searchField, defaultValue: d.searchField, disabled: disabled)
            RadiusRow(label: "Tab button", value: $editorState.theme.cornerRadii.tabButton, defaultValue: d.tabButton, disabled: disabled)
            RadiusRow(label: "Picker row", value: $editorState.theme.cornerRadii.pickerRow, defaultValue: d.pickerRow, disabled: disabled)
            RadiusRow(label: "Shortcut record field", value: $editorState.theme.cornerRadii.shortcutRecordField, defaultValue: d.shortcutRecordField, disabled: disabled)
            RadiusRow(label: "Key badge", value: $editorState.theme.cornerRadii.keyBadge, defaultValue: d.keyBadge, disabled: disabled)
            RadiusRow(label: "Gauge", value: $editorState.theme.cornerRadii.gauge, defaultValue: d.gauge, disabled: disabled)
        }
    }

    // MARK: - Spacing Section

    private var spacingSection: some View {
        builderCard("Spacing") {
            let disabled = editorState.isBuiltIn
            let d = Theme.Spacing.default
            SpacingRow(label: "Panel padding", value: $editorState.theme.spacing.panelPadding, range: 4...28, defaultValue: d.panelPadding, disabled: disabled)
            SpacingRow(label: "Section spacing", value: $editorState.theme.spacing.sectionSpacing, range: 4...28, defaultValue: d.sectionSpacing, disabled: disabled)
            SpacingRow(label: "Content area padding", value: $editorState.theme.spacing.contentAreaPadding, range: 4...28, defaultValue: d.contentAreaPadding, disabled: disabled)
            SpacingRow(label: "Row horizontal padding", value: $editorState.theme.spacing.rowHorizontalPadding, range: 2...20, defaultValue: d.rowHorizontalPadding, disabled: disabled)
            SpacingRow(label: "Row vertical padding", value: $editorState.theme.spacing.rowVerticalPadding, range: 2...20, defaultValue: d.rowVerticalPadding, disabled: disabled)
            SpacingRow(label: "Row spacing", value: $editorState.theme.spacing.rowSpacing, range: 0...10, defaultValue: d.rowSpacing, disabled: disabled)
            SpacingRow(label: "Row details spacing", value: $editorState.theme.spacing.rowDetailsSpacing, range: 0...16, defaultValue: d.rowDetailsSpacing, disabled: disabled)
            SpacingRow(label: "Separator thickness", value: $editorState.theme.spacing.separatorThickness, range: 1...8, defaultValue: d.separatorThickness, disabled: disabled)
        }
    }

    // MARK: - Fonts Section

    private var fontsSection: some View {
        builderCard("Fonts") {
            let disabled = editorState.isBuiltIn
            Text("Row text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FontSpecRow(label: "Family", spec: $editorState.theme.fonts.row, defaultSize: 13, defaultWeight: "regular", disabled: disabled)
            Divider().padding(.vertical, 2)
            Text("Monospace row text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FontSpecRow(label: "Family", spec: $editorState.theme.fonts.rowMono, defaultSize: 12, defaultWeight: "regular", disabled: disabled)
        }
    }

    // MARK: - Card / Row Helpers

    @ViewBuilder
    private func builderCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        @Environment(\.theme) var t
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: t.cornerRadii.card, style: .continuous)
                    .fill(t.resolvedCardFill)
            )
            .overlay {
                let border = t.resolvedCardBorder
                if border.isVisible {
                    RoundedRectangle(cornerRadius: t.cornerRadii.card, style: .continuous)
                        .stroke(border.color, style: border.strokeStyle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func builderRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            control()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func builderToggle(_ label: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        HStack {
            Toggle(isOn: isOn) {
                Text(label).font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(disabled)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func builderSubHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

// MARK: - Fill Editor

private struct FillEditorRow: View {
    let label: String
    @Binding var fill: ThemeFill
    let disabled: Bool
    var defaultFill: ThemeFill? = nil
    var accentHex: String = "#FFFFFF"

    private var isDefault: Bool { defaultFill.map { fill == $0 } ?? false }

    private enum FillKind: String, CaseIterable {
        case solid = "Solid"
        case linear = "Gradient"
        case mesh = "Mesh"
    }

    private var kind: FillKind {
        if fill.mesh != nil { return .mesh }
        if fill.gradient != nil { return .linear }
        return .solid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if defaultFill != nil {
                        if isDefault { defaultBadge("default") }
                        else {
                            changedBadge()
                            resetButton(tooltip: "Reset to default") { fill = defaultFill! }
                                .disabled(disabled)
                        }
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { kind },
                        set: { switchKind(to: $0) }
                    )) {
                        ForEach(FillKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 180)
                    .disabled(disabled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }

            Group {
                switch kind {
                case .solid: solidEditor
                case .linear: linearEditor
                case .mesh: meshEditor
                }
            }
            .padding(.leading, 16)
            .disabled(disabled)
        }
    }

    private var solidEditor: some View {
        HStack(spacing: 0) {
            ColorPickerRow(label: "", hex: Binding(
                get: { fill.color ?? accentHex },
                set: { fill.color = $0; fill.gradient = nil; fill.mesh = nil }
            ))
            OpacitySlider(value: Binding(
                get: { fill.opacity ?? 1.0 },
                set: { fill.opacity = $0 }
            ))
        }
        .padding(.bottom, 4)
    }

    private var linearEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            let colors = fill.gradient ?? ["#FFFFFF", "#000000"]
            ForEach(Array(colors.enumerated()), id: \.offset) { idx, hex in
                HStack(spacing: 8) {
                    Text("Stop \(idx + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    ColorPickerRow(label: "", hex: Binding(
                        get: { hex },
                        set: { newHex in
                            var c = fill.gradient ?? colors
                            if c.indices.contains(idx) { c[idx] = newHex }
                            fill.gradient = c
                        }
                    ))
                    if colors.count > 2 {
                        Button { removeGradientStop(at: idx) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                var c = fill.gradient ?? colors
                c.append(c.last ?? "#FFFFFF")
                fill.gradient = c
            } label: {
                Label("Add stop", systemImage: "plus.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Direction")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { fill.from ?? "top" },
                    set: { fill.from = $0 }
                )) {
                    ForEach(["top","bottom","leading","trailing","topLeading","topTrailing","bottomLeading","bottomTrailing"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Picker("", selection: Binding(
                    get: { fill.to ?? "bottom" },
                    set: { fill.to = $0 }
                )) {
                    ForEach(["top","bottom","leading","trailing","topLeading","topTrailing","bottomLeading","bottomTrailing"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            OpacitySlider(value: Binding(
                get: { fill.opacity ?? 1.0 },
                set: { fill.opacity = $0 }
            ), horizontalPadding: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    private var meshEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Columns")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Stepper("\(fill.meshColumns ?? 3)", value: Binding(
                        get: { fill.meshColumns ?? 3 },
                        set: { newCols in
                            let rows = fill.meshRows ?? 3
                            fill.meshColumns = newCols
                            fill.mesh = resizedMeshColors(cols: newCols, rows: rows)
                        }
                    ), in: 2...4)
                    .font(.system(size: 11, weight: .medium))
                }
                HStack(spacing: 4) {
                    Text("Rows")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Stepper("\(fill.meshRows ?? 3)", value: Binding(
                        get: { fill.meshRows ?? 3 },
                        set: { newRows in
                            let cols = fill.meshColumns ?? 3
                            fill.meshRows = newRows
                            fill.mesh = resizedMeshColors(cols: cols, rows: newRows)
                        }
                    ), in: 2...4)
                    .font(.system(size: 11, weight: .medium))
                }
            }

            let cols = fill.meshColumns ?? 3
            let rows = fill.meshRows ?? 3
            let colors = meshColorsPadded(cols: cols, rows: rows)

            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { col in
                            let idx = row * cols + col
                            ColorPickerRow(label: "", hex: Binding(
                                get: { colors[idx] },
                                set: { newHex in
                                    var c = meshColorsPadded(cols: cols, rows: rows)
                                    c[idx] = newHex
                                    fill.mesh = c
                                }
                            ))
                        }
                    }
                }
            }

            OpacitySlider(value: Binding(
                get: { fill.opacity ?? 1.0 },
                set: { fill.opacity = $0 }
            ))

            if #unavailable(macOS 15) {
                Text("Mesh gradients require macOS 15+. A diagonal gradient is shown as fallback.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    private func resizedMeshColors(cols: Int, rows: Int) -> [String] {
        let old = fill.mesh ?? []
        let count = cols * rows
        var result = [String](repeating: "#000000", count: count)
        for i in 0..<min(count, old.count) { result[i] = old[i] }
        return result
    }

    private func meshColorsPadded(cols: Int, rows: Int) -> [String] {
        let count = cols * rows
        let existing = fill.mesh ?? []
        if existing.count == count { return existing }
        var result = [String](repeating: "#000000", count: count)
        for i in 0..<min(count, existing.count) { result[i] = existing[i] }
        return result
    }

    private func removeGradientStop(at index: Int) {
        var c = fill.gradient ?? []
        guard c.indices.contains(index) else { return }
        c.remove(at: index)
        fill.gradient = c
    }

    private func switchKind(to newKind: FillKind) {
        switch newKind {
        case .solid:
            let c = fill.gradient?.first ?? fill.mesh?.first ?? accentHex
            fill = .solid(c, opacity: fill.opacity)
        case .linear:
            let first = fill.color ?? fill.mesh?.first ?? accentHex
            let last = fill.mesh?.last ?? "#000000"
            fill = .linearGradient([first, last], opacity: fill.opacity)
        case .mesh:
            let base = fill.color ?? fill.gradient?.first ?? accentHex
            fill = .meshGradient([String](repeating: base, count: 9), columns: 3, rows: 3, opacity: fill.opacity)
        }
    }
}

// MARK: Optional Fill

private struct OptionalFillEditorRow: View {
    let label: String
    @Binding var fill: ThemeFill?
    let disabled: Bool
    var defaultValue: ThemeFill? = nil
    var defaultLabel: String = "default"

    private var isDefault: Bool { fill == defaultValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(
                    get: { fill != nil },
                    set: { fill = $0 ? .solid("#FFFFFF", opacity: 0.15) : nil }
                )) {
                    Text(label).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(disabled)
                if isDefault { defaultBadge(defaultLabel) }
                else {
                    changedBadge()
                    resetButton(tooltip: "Reset to default") { fill = defaultValue }
                        .disabled(disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            if var unwrapped = fill {
                DependentGroup(enabled: true) {
                    FillEditorRow(label: "", fill: Binding(
                        get: { unwrapped },
                        set: {
                            unwrapped = $0
                            fill = $0
                        }
                    ), disabled: disabled)
                }
            } else {
                DependentGroup(enabled: false) {
                    FillEditorRow(label: "", fill: .constant(.solid("#FFFFFF", opacity: 0.15)), disabled: disabled)
                }
            }
        }
    }
}

// MARK: - Border Editor

private struct BorderEditorRow: View {
    let label: String
    @Binding var border: ThemeBorder?
    let disabled: Bool
    var defaultValue: ThemeBorder? = nil

    private var isDefault: Bool { border == defaultValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(
                    get: { border != nil },
                    set: { border = $0 ? ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.3) : nil }
                )) {
                    Text(label).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(disabled)
                if isDefault { defaultBadge("default") }
                else {
                    changedBadge()
                    resetButton(tooltip: "Reset to default") { border = defaultValue }
                        .disabled(disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            DependentGroup(enabled: border != nil) {
                VStack(alignment: .leading, spacing: 4) {
                    ColorPickerRow(
                        label: "Color",
                        hex: Binding(
                            get: { border?.color ?? "#FFFFFF" },
                            set: { border?.color = $0 }
                        )
                    )
                    LabeledSliderRow(
                        label: "Width",
                        value: Binding(
                            get: { Double(border?.width ?? 1) },
                            set: { border?.width = CGFloat($0) }
                        ),
                        range: 0...4, step: 0.5,
                        format: "%.1f pt"
                    )
                    OpacitySlider(value: Binding(
                        get: { border?.opacity ?? 1.0 },
                        set: { border?.opacity = $0 }
                    ))

                    HStack(spacing: 8) {
                        Text("Dash (e.g. 6, 2)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("", text: Binding(
                            get: { border?.dash?.map { "\(Int($0))" }.joined(separator: ", ") ?? "" },
                            set: { str in
                                let nums = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                                border?.dash = nums.isEmpty ? nil : nums.map { CGFloat($0) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 100)
                    }
                    .padding(.horizontal, 8)

                    HStack(spacing: 8) {
                        Text("Animation")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { border?.animation ?? "none" },
                            set: { border?.animation = $0 == "none" ? nil : $0 }
                        )) {
                            Text("None").tag("none")
                            Text("Flash").tag("flash")
                            Text("Sweep").tag("sweep")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 8)

                    DependentGroup(enabled: border?.animation != nil) {
                        LabeledSliderRow(
                            label: "Duration",
                            value: Binding(
                                get: { border?.animationDuration ?? 0.6 },
                                set: { border?.animationDuration = $0 }
                            ),
                            range: 0.1...3.0, step: 0.1,
                            format: "%.1f s"
                        )
                    }
                }
                .disabled(disabled)
            }
        }
    }
}

// MARK: - Glow Editor

private struct GlowEditorRow: View {
    let label: String
    @Binding var glow: ThemeGlow?
    let disabled: Bool
    var defaultValue: ThemeGlow? = nil

    private var isDefault: Bool { glow == defaultValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(
                    get: { glow != nil },
                    set: { glow = $0 ? ThemeGlow(color: "#FFFFFF", radius: 8, opacity: 0.5) : nil }
                )) {
                    Text(label).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(disabled)
                if isDefault { defaultBadge("default") }
                else {
                    changedBadge()
                    resetButton(tooltip: "Reset to default") { glow = defaultValue }
                        .disabled(disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            DependentGroup(enabled: glow != nil) {
                VStack(alignment: .leading, spacing: 4) {
                    ColorPickerRow(
                        label: "Color",
                        hex: Binding(
                            get: { glow?.color ?? "#FFFFFF" },
                            set: { glow?.color = $0 }
                        )
                    )
                    LabeledSliderRow(
                        label: "Radius",
                        value: Binding(
                            get: { Double(glow?.radius ?? 8) },
                            set: { glow?.radius = CGFloat($0) }
                        ),
                        range: 0...30, step: 1,
                        format: "%.0f"
                    )
                    OpacitySlider(value: Binding(
                        get: { glow?.opacity ?? 0.5 },
                        set: { glow?.opacity = $0 }
                    ))

                    // Inner glow
                    HStack {
                        Toggle(isOn: Binding(
                            get: { glow?.innerRadius != nil },
                            set: {
                                if $0 {
                                    glow?.innerRadius = 3
                                    glow?.innerOpacity = 0.8
                                } else {
                                    glow?.innerRadius = nil
                                    glow?.innerOpacity = nil
                                }
                            }
                        )) {
                            Text("Inner glow layer")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                    }
                    .padding(.horizontal, 8)

                    DependentGroup(enabled: glow?.innerRadius != nil) {
                        LabeledSliderRow(
                            label: "Inner radius",
                            value: Binding(
                                get: { Double(glow?.innerRadius ?? 3) },
                                set: { glow?.innerRadius = CGFloat($0) }
                            ),
                            range: 0...20, step: 0.5,
                            format: "%.1f"
                        )
                        OpacitySlider(
                            label: "Inner opacity",
                            value: Binding(
                                get: { glow?.innerOpacity ?? 0.8 },
                                set: { glow?.innerOpacity = $0 }
                            )
                        )
                    }
                }
                .disabled(disabled)
            }
        }
    }
}

// MARK: - Inner Shadow Editor

private struct InnerShadowEditorRow: View {
    let label: String
    @Binding var shadow: ThemeInnerShadow?
    let disabled: Bool

    private var isDefault: Bool { shadow == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(
                    get: { shadow != nil },
                    set: { shadow = $0 ? ThemeInnerShadow(color: "#000000", radius: 4, opacity: 0.4) : nil }
                )) {
                    Text(label).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(disabled)
                if isDefault { defaultBadge("default") }
                else {
                    changedBadge()
                    resetButton(tooltip: "Remove inner shadow") { shadow = nil }
                        .disabled(disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            DependentGroup(enabled: shadow != nil) {
                VStack(alignment: .leading, spacing: 4) {
                    ColorPickerRow(
                        label: "Color",
                        hex: Binding(
                            get: { shadow?.color ?? "#000000" },
                            set: { shadow?.color = $0 }
                        )
                    )
                    OpacitySlider(value: Binding(
                        get: { shadow?.opacity ?? 0.4 },
                        set: { shadow?.opacity = $0 }
                    ))
                    LabeledSliderRow(
                        label: "Radius",
                        value: Binding(
                            get: { Double(shadow?.radius ?? 4) },
                            set: { shadow?.radius = CGFloat($0) }
                        ),
                        range: 1...20, step: 1,
                        format: "%.0f"
                    )
                    LabeledSliderRow(
                        label: "Offset X",
                        value: Binding(
                            get: { Double(shadow?.x ?? 0) },
                            set: { shadow?.x = CGFloat($0) }
                        ),
                        range: -20...20, step: 1,
                        format: "%.0f"
                    )
                    LabeledSliderRow(
                        label: "Offset Y",
                        value: Binding(
                            get: { Double(shadow?.y ?? 0) },
                            set: { shadow?.y = CGFloat($0) }
                        ),
                        range: -20...20, step: 1,
                        format: "%.0f"
                    )
                }
            }
        }
    }
}

// MARK: - Radius / Spacing Rows

private struct RadiusRow: View {
    let label: String
    @Binding var value: CGFloat
    let defaultValue: CGFloat
    let disabled: Bool

    var body: some View {
        LabeledSliderRow(
            label: label,
            value: Binding(get: { Double(value) }, set: { value = CGFloat($0) }),
            range: 0...28, step: 1,
            format: "%.0f",
            disabled: disabled,
            trailingReset: value != defaultValue && !disabled ? { value = defaultValue } : nil,
            trailingResetTooltip: "Reset to default (\(Int(defaultValue)))",
            showDefaultBadge: value == defaultValue
        )
    }
}

private struct FontSpecRow: View {
    let label: String
    @Binding var spec: Theme.FontSpec
    let defaultSize: Double
    let defaultWeight: String
    let disabled: Bool

    private let weights = ["regular", "medium", "semibold", "bold"]

    var body: some View {
        VStack(spacing: 6) {
            // Family swatch + weight picker in one row
            HStack(spacing: 8) {
                FontSwatch(spec: $spec, defaultSize: defaultSize)
                    .disabled(disabled)
                Picker("", selection: Binding(
                    get: { spec.weight ?? defaultWeight },
                    set: { spec.weight = $0 == defaultWeight ? nil : $0 }
                )) {
                    ForEach(weights, id: \.self) { w in
                        Text(w.capitalized).tag(w)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(disabled)
                if spec.family != nil || spec.weight != nil {
                    changedBadge()
                    if !disabled {
                        resetButton(tooltip: "Reset to system font") { spec.family = nil; spec.weight = nil }
                    }
                }
                Spacer()
            }
            // Size
            LabeledSliderRow(
                label: "Size",
                value: Binding(
                    get: { spec.size ?? defaultSize },
                    set: { spec.size = $0 == defaultSize ? nil : $0 }
                ),
                range: 8...22, step: 0.5,
                format: "%.1f",
                disabled: disabled,
                trailingReset: spec.size != nil && !disabled ? { spec.size = nil } : nil,
                trailingResetTooltip: "Reset to default (\(Int(defaultSize))pt)",
                showDefaultBadge: spec.size == nil
            )
        }
        .padding(.vertical, 2)
    }
}

private struct SpacingRow: View {
    let label: String
    @Binding var value: CGFloat
    var range: ClosedRange<Double>
    let defaultValue: CGFloat
    let disabled: Bool

    var body: some View {
        LabeledSliderRow(
            label: label,
            value: Binding(get: { Double(value) }, set: { value = CGFloat($0) }),
            range: range, step: 1,
            format: "%.0f",
            disabled: disabled,
            trailingReset: value != defaultValue && !disabled ? { value = defaultValue } : nil,
            trailingResetTooltip: "Reset to default (\(Int(defaultValue)))",
            showDefaultBadge: value == defaultValue
        )
    }
}

// MARK: - Primitive Controls

private func defaultBadge(_ label: String) -> some View {
    Text(label)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.secondary.opacity(0.12)))
}

private func changedBadge() -> some View {
    Text("changed")
        .font(.system(size: 10))
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.orange.opacity(0.12)))
}

private func resetButton(tooltip: String = "Reset to default", action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .help(tooltip)
}

private struct ColorPickerRow: View {
    let label: String
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            ColorSwatch(hex: $hex)

            TextField("", text: $hex)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 58)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

/// A color swatch that opens NSColorPanel when clicked.
private struct ColorSwatch: View {
    @Binding var hex: String

    var body: some View {
        (Color(hex: hex) ?? .white)
            .frame(width: 20, height: 20)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
            .onTapGesture { Self.openColorPanel(hex: $hex) }
    }

    static func openColorPanel(hex: Binding<String>) {
        let panel = NSColorPanel.shared
        // Clear the action before changing the color to prevent the stale
        // callback from firing and writing the new initial color into the
        // previously-active binding.
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.color = NSColor(Color(hex: hex.wrappedValue) ?? .white)
        panel.makeKeyAndOrderFront(nil)
        panel.setAction(#selector(ColorPanelReceiver.colorChanged(_:)))
        panel.setTarget(ColorPanelReceiver.shared)
        ColorPanelReceiver.shared.onColorChange = { color in
            hex.wrappedValue = color.hexString
        }
    }
}

/// A font swatch that opens NSFontPanel when clicked.
/// Shows the selected family name rendered in that font.
private struct FontSwatch: View {
    @Binding var spec: Theme.FontSpec
    let defaultSize: Double

    var body: some View {
        let nsFont = spec.family.flatMap { NSFont(name: $0, size: 12) } ?? NSFont.systemFont(ofSize: 12)
        Text(spec.family ?? "System")
            .font(Font(nsFont))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
            .onTapGesture {
                FontPanelReceiver.openFontPanel(spec: $spec, defaultSize: defaultSize)
            }
    }
}

/// Singleton AppKit target that bridges NSColorPanel color changes to the active swatch.
@MainActor
private final class ColorPanelReceiver: NSObject {
    static let shared = ColorPanelReceiver()
    var onColorChange: ((NSColor) -> Void)?

    @objc func colorChanged(_ sender: NSColorPanel) {
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        onColorChange?(color)
    }
}

/// Singleton AppKit target that bridges NSFontManager font changes to the active font spec.
@MainActor
private final class FontPanelReceiver: NSObject {
    static let shared = FontPanelReceiver()
    var onFontChange: ((_ family: String?, _ weight: String) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let manager = sender else { return }
        // Convert a neutral base font through the manager to obtain the user's selection.
        let base = NSFont.systemFont(ofSize: NSFontManager.shared.selectedFont?.pointSize ?? 13)
        let selected = manager.convert(base)
        let family: String? = selected.familyName
        let traits = manager.traits(of: selected)
        let weight: String = traits.contains(.boldFontMask) ? "bold" : "regular"
        onFontChange?(family, weight)
    }

    static func openFontPanel(spec: Binding<Theme.FontSpec>, defaultSize: Double) {
        let manager = NSFontManager.shared
        // Clear target/action first so the stale closure doesn't fire on font pre-selection.
        manager.target = nil
        manager.action = #selector(NSObject.doesNotRecognizeSelector(_:))  // no-op sentinel
        // Pre-select the current font in the panel.
        let size = CGFloat(spec.wrappedValue.size ?? defaultSize)
        let nsFont: NSFont
        if let family = spec.wrappedValue.family, !family.isEmpty,
           let f = NSFont(name: family, size: size) {
            nsFont = f
        } else {
            nsFont = .systemFont(ofSize: size)
        }
        manager.setSelectedFont(nsFont, isMultiple: false)
        NSFontPanel.shared.makeKeyAndOrderFront(nil)
        // Position the font panel centered on the theme builder window.
        if let builderFrame = ThemeBuilderWindowController.shared.windowFrame,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(builderFrame) }) ?? NSScreen.main {
            let panelSize = NSFontPanel.shared.frame.size
            let sv = screen.visibleFrame
            let x = max(sv.minX, min(builderFrame.midX - panelSize.width / 2, sv.maxX - panelSize.width))
            let y = max(sv.minY, min(builderFrame.midY - panelSize.height / 2, sv.maxY - panelSize.height))
            NSFontPanel.shared.setFrameOrigin(NSPoint(x: x, y: y))
        }
        manager.target = FontPanelReceiver.shared
        manager.action = #selector(FontPanelReceiver.changeFont(_:))
        FontPanelReceiver.shared.onFontChange = { family, weight in
            spec.wrappedValue.family = family
            spec.wrappedValue.weight = weight
        }
    }
}

private struct OptionalColorRow: View {
    let label: String
    @Binding var hex: String?
    let disabled: Bool
    var defaultColor: Color = .secondary
    var defaultLabel: String = "default"

    private var isDefault: Bool { hex == nil }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12))
            if isDefault {
                defaultBadge(defaultLabel)
            } else {
                changedBadge()
                resetButton(tooltip: "Reset to default (\(defaultLabel))") { hex = nil }
                    .disabled(disabled)
            }
            Spacer()
            ColorPickerRow(label: "", hex: Binding(
                get: { hex ?? defaultColor.hexString },
                set: { hex = $0 }
            ))
            .disabled(disabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct OptionalColorOpacityRow: View {
    let label: String
    @Binding var hex: String?
    @Binding var opacity: Double?
    let defaultOpacity: Double
    let disabled: Bool
    var defaultColor: Color = .secondary
    var defaultLabel: String = "default"

    private var isDefault: Bool { hex == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 12))
                if isDefault {
                    defaultBadge(defaultLabel)
                } else {
                    changedBadge()
                    resetButton(tooltip: "Reset to default (\(defaultLabel))") { hex = nil; opacity = nil }
                        .disabled(disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            HStack(spacing: 0) {
                ColorPickerRow(label: "", hex: Binding(
                    get: { hex ?? defaultColor.hexString },
                    set: { hex = $0 }
                ))
                .disabled(disabled)
                OpacitySlider(value: Binding(
                    get: { opacity ?? defaultOpacity },
                    set: {
                        if hex == nil { hex = defaultColor.hexString }
                        opacity = $0
                    }
                ))
                .disabled(disabled)
            }
            .padding(.leading, 16)
            .padding(.bottom, 4)
        }
    }
}

private struct OptionalDoubleRow: View {
    let label: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let disabled: Bool

    @State private var editText: String
    @FocusState private var isFocused: Bool

    init(label: String, value: Binding<Double?>, range: ClosedRange<Double>, step: Double, disabled: Bool) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.disabled = disabled
        let fmt = (step >= 1 && step == step.rounded()) ? "%.0f" : "%.1f"
        self._editText = State(initialValue: value.wrappedValue.map { String(format: fmt, $0) } ?? "")
    }

    private var isIntegerStep: Bool { step >= 1 && step == step.rounded() }
    private var displayFormat: String { isIntegerStep ? "%.0f" : "%.1f" }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { value != nil },
                set: { value = $0 ? range.lowerBound : nil }
            )) {
                Text(label).font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(disabled)
            Spacer()
            if value != nil {
                if isIntegerStep {
                    Slider(
                        value: Binding(get: { value ?? range.lowerBound }, set: { value = $0 }),
                        in: range, step: step
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Slider(
                        value: Binding(get: { value ?? range.lowerBound }, set: { value = $0 }),
                        in: range
                    )
                    .frame(maxWidth: .infinity)
                }
                TextField("", text: $editText)
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .disabled(disabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .onChange(of: value) { _, v in if !isFocused, let v { editText = String(format: displayFormat, v) } }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        if let parsed = Double(editText.trimmingCharacters(in: .whitespaces)) {
            value = max(range.lowerBound, min(range.upperBound, parsed))
        }
        if let v = value { editText = String(format: displayFormat, v) }
    }
}

private struct OpacitySlider: View {
    var label: String = "Opacity"
    @Binding var value: Double
    var compact: Bool = false
    var horizontalPadding: CGFloat = 8

    var body: some View {
        LabeledSliderRow(label: label, value: $value, range: 0...1, step: 0.01, format: "%.2f", verticalPadding: compact ? 1 : 3, horizontalPadding: horizontalPadding)
    }
}

private struct LabeledSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    var disabled: Bool = false
    var labelWidth: CGFloat? = 90
    var verticalPadding: Double = 3
    var horizontalPadding: CGFloat = 8
    var trailingReset: (() -> Void)? = nil
    var trailingResetTooltip: String = "Reset to default"
    var showDefaultBadge: Bool = false

    @State private var editText: String
    @FocusState private var isFocused: Bool

    init(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
         format: String, disabled: Bool = false, labelWidth: CGFloat? = 90, verticalPadding: Double = 3,
         horizontalPadding: CGFloat = 8, trailingReset: (() -> Void)? = nil, trailingResetTooltip: String = "Reset to default",
         showDefaultBadge: Bool = false) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.disabled = disabled
        self.labelWidth = labelWidth
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.trailingReset = trailingReset
        self.trailingResetTooltip = trailingResetTooltip
        self.showDefaultBadge = showDefaultBadge
        let numFmt = format.components(separatedBy: " ").first ?? format
        self._editText = State(initialValue: String(format: numFmt, value.wrappedValue))
    }

    // Strip any non-numeric suffix (e.g. " pt", " s") so we can parse the number.
    private var numericFormat: String {
        format.components(separatedBy: " ").first ?? format
    }

    // Only use discrete steps for integer sliders; float sliders render continuously.
    private var isIntegerStep: Bool { step >= 1 && step == step.rounded() }

    var body: some View {
        HStack(spacing: 6) {
            if let w = labelWidth {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: w, alignment: .leading)
            } else {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if let reset = trailingReset {
                changedBadge()
                resetButton(tooltip: trailingResetTooltip, action: reset)
            } else if showDefaultBadge {
                defaultBadge("default")
            }
            if isIntegerStep {
                Slider(value: $value, in: range, step: step)
                    .disabled(disabled)
                    .frame(maxWidth: .infinity)
            } else {
                Slider(value: $value, in: range)
                    .disabled(disabled)
                    .frame(maxWidth: .infinity)
            }
            TextField("", text: $editText)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 46)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commit() }
                .disabled(disabled)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .onChange(of: value) { _, v in if !isFocused { editText = String(format: numericFormat, v) } }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        if let parsed = Double(editText.trimmingCharacters(in: .whitespaces)) {
            value = max(range.lowerBound, min(range.upperBound, parsed))
        }
        editText = String(format: numericFormat, value)
    }
}

// MARK: - Helpers

private extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Sets all NSScrollViews in the theme builder's own window to overlay scroller style.
private struct ThemeBuilderScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let root = nsView.window?.contentView else { return }
            func apply(_ view: NSView) {
                if let sv = view as? NSScrollView { sv.scrollerStyle = .overlay; sv.tile() }
                view.subviews.forEach { apply($0) }
            }
            apply(root)
        }
    }
}

private extension Color {
    var hexString: String {
        (NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)).hexString
    }
}
