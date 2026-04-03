import AppKit
import SwiftUI

struct SettingsView: View {
    private let cooldownOptions = [100, 200, 350, 500, 750, 1_000, 1_500, 2_000]
    private let selectionBufferOptions = [1, 2, 3, 5, 10]
    private let historyLimitOptions = [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
    private let itemLineLimitOptions = [1, 2, 3, 4]

    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    generalSection
                    copyOnSelectSection
                    richTextSection
                }

                HStack(alignment: .top, spacing: 12) {
                    appearanceSection
                    shortcutsSection
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if theme.options.useMaterial {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            } else {
                Rectangle().fill(theme.resolvedPanelFill).ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        settingsCard("General") {
            settingsToggleRow(
                title: "Monitor clipboard",
                isOn: Binding(
                    get: { appState.settings.isClipboardMonitoringEnabled },
                    set: { appState.settings.isClipboardMonitoringEnabled = $0 }
                )
            )

            settingsToggleRow(
                title: "Move to top on paste",
                help: "When you paste an item, move it to the top of your history so recent pastes are always first.",
                isOn: Binding(
                    get: { appState.settings.moveToTopOnPaste },
                    set: { appState.settings.moveToTopOnPaste = $0 }
                )
            )

            settingsToggleRow(
                title: "Not for favorites",
                help: "Favorites are not moved to the top when pasted.",
                isOn: Binding(
                    get: { appState.settings.moveToTopSkipFavorites },
                    set: { appState.settings.moveToTopSkipFavorites = $0 }
                )
            )
            .padding(.leading, 16)
            .disabled(!appState.settings.moveToTopOnPaste)

            settingMetric(title: "History limit") {
                optionPicker(
                    selection: Binding(
                        get: { appState.settings.historyLimit },
                        set: { appState.settings.historyLimit = $0 }
                    ),
                    options: historyLimitOptions,
                    label: { "\($0)" }
                )
            }

            settingMetric(
                title: "Ignored apps",
                help: "Clipboard entries from these apps will not be captured. Applies to both clipboard monitoring and copy-on-select."
            ) {
                IgnoredBundleIDsConfigButton(ignoredBundleIDs: Binding(
                    get: { appState.settings.ignoredBundleIDs.joined(separator: ", ") },
                    set: {
                        appState.settings.ignoredBundleIDs = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                ))
            }

            Group {
                if appState.settings.ignoredBundleIDs.isEmpty {
                    Text("none")
                        .font(.system(size: 10).italic())
                        .foregroundStyle(.tertiary)
                } else {
                    Text(appState.settings.ignoredBundleIDs.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
    }

    private var appearanceSection: some View {
        settingsCard("Appearance") {
            settingMetric(title: "Theme", help: "Themes are JSON files in ~/Library/Application Support/Clipiary/themes/. Copy and edit default.json to create your own. Ctrl+R in main window to reload selected theme.") {
                Picker("", selection: Binding(
                    get: { appState.settings.selectedThemeID },
                    set: { appState.settings.selectedThemeID = $0 }
                )) {
                    ForEach(appState.themeManager.availableThemes, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

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
                title: "Show favorite tab badges",
                isOn: Binding(
                    get: { appState.settings.showFavoriteTabBadges },
                    set: { appState.settings.showFavoriteTabBadges = $0 }
                )
            )

            settingsToggleRow(
                title: "Always show search field",
                isOn: Binding(
                    get: { appState.settings.alwaysShowSearch },
                    set: { appState.settings.alwaysShowSearch = $0 }
                )
            )

            settingMetric(title: "Item line limit") {
                optionPicker(
                    selection: Binding(
                        get: { appState.settings.itemLineLimit },
                        set: { appState.settings.itemLineLimit = $0 }
                    ),
                    options: itemLineLimitOptions,
                    label: { "\($0)" }
                )
            }

            settingMetric(title: "Paste count bar", help: "A colored bar on each item showing how often you paste it. Helps you spot your most-used clips.") {
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
            }

            settingsToggleRow(
                title: "Auto monospace from terminals/IDEs",
                help: "Automatically use a monospace font for items copied from terminals and IDEs.",
                isOn: Binding(
                    get: { appState.settings.autoMonospaceFromTerminals },
                    set: { appState.settings.autoMonospaceFromTerminals = $0 }
                ),
                extra: appState.settings.autoMonospaceFromTerminals ? AnyView(
                    TerminalBundleIDsConfigButton(terminalBundleIDs: Binding(
                        get: { appState.settings.terminalBundleIDs },
                        set: { appState.settings.terminalBundleIDs = $0 }
                    ))
                ) : nil
            )

            if appState.settings.autoMonospaceFromTerminals {
                Text(appState.settings.terminalBundleIDs)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var copyOnSelectSection: some View {
        settingsCard("Copy on Select") {
            settingsToggleRow(
                title: "Enable globally (best effort)",
                help: "Automatically capture text you select in any app, without pressing Cmd+C. Requires Accessibility access.",
                isOn: Binding(
                    get: { appState.settings.isCopyOnSelectEnabled },
                    set: { appState.settings.isCopyOnSelectEnabled = $0 }
                )
            )

            if appState.settings.isCopyOnSelectEnabled && !appState.permissionManager.isTrusted {
                Button {
                    appState.refreshCopyOnSelectPermissions()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(nsColor: .systemOrange))
                            .frame(width: 6, height: 6)
                        Text("Grant Accessibility Access")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            settingMetric(title: "Minimum selection length", help: "Ignore selections shorter than this many characters to avoid capturing accidental clicks.") {
                Stepper(
                    "\(appState.settings.minimumSelectionLength)",
                    value: Binding(
                        get: { appState.settings.minimumSelectionLength },
                        set: { appState.settings.minimumSelectionLength = max(1, $0) }
                    ),
                    in: 1...10
                )
                .font(.system(size: 11, weight: .medium))
            }

            settingMetric(title: "Cooldown", help: "Wait this long after a selection changes before capturing it. Prevents flooding your history while you drag to select text.") {
                optionPicker(
                    selection: Binding(
                        get: { appState.settings.copyOnSelectCooldownMilliseconds },
                        set: { appState.settings.copyOnSelectCooldownMilliseconds = $0 }
                    ),
                    options: cooldownOptions,
                    label: { "\($0) ms" }
                )
            }

            settingMetric(title: "Keep unused items", help: "How many copy-on-select items to keep if you never paste them. They are automatically removed once this limit is exceeded.") {
                optionPicker(
                    selection: Binding(
                        get: { appState.settings.copyOnSelectBufferLimit },
                        set: { appState.settings.copyOnSelectBufferLimit = $0 }
                    ),
                    options: selectionBufferOptions,
                    label: { "\($0)" }
                )
            }
        }
    }

    private var richTextSection: some View {
        settingsCard("Rich Text") {
            settingsToggleRow(
                title: "Capture rich text (RTF/HTML)",
                help: "When enabled, Clipiary also stores rich text formatting from the clipboard. Items with rich text show an RTF or HTML badge.",
                isOn: Binding(
                    get: { appState.settings.isRichTextCaptureEnabled },
                    set: { appState.settings.isRichTextCaptureEnabled = $0 }
                )
            )

            settingsToggleRow(
                title: "Paste rich text by default",
                help: "When pasting, use RTF/HTML formatting if available. Use the alternate paste shortcut to paste plain text instead.",
                isOn: Binding(
                    get: { appState.settings.richTextPasteDefault },
                    set: { appState.settings.richTextPasteDefault = $0 }
                )
            )
            .padding(.leading, 16)
            .disabled(!appState.settings.isRichTextCaptureEnabled)
        }
    }

    private var shortcutsSection: some View {        settingsCard("Shortcuts") {
            shortcutRow(
                title: "Open Clipiary",
                value: appState.isRecordingShortcut ? "Press keys..." : appState.settings.globalShortcut.displayString,
                isRecording: appState.isRecordingShortcut
            ) {
                appState.isRecordingShortcut.toggle()
            }

            shortcutRow(
                title: "Quick paste previous",
                help: "Instantly paste the second-most-recent item in your history without opening Clipiary.",
                value: appState.isRecordingQuickPasteShortcut ? "Press keys..." : appState.settings.quickPasteShortcut.displayString,
                isRecording: appState.isRecordingQuickPasteShortcut
            ) {
                appState.isRecordingQuickPasteShortcut.toggle()
            }

            shortcutRow(
                title: "Alt paste (in panel)",
                help: "While Clipiary is open, pastes the opposite of your default format (rich text ↔ plain text).",
                value: appState.isRecordingLocalAltPasteShortcut ? "Press keys..." : appState.settings.localAltPasteShortcut.displayString,
                isRecording: appState.isRecordingLocalAltPasteShortcut
            ) {
                appState.isRecordingLocalAltPasteShortcut.toggle()
            }

            shortcutRow(
                title: "Alt paste (global)",
                help: "Pastes the most-recent clipboard item in the opposite of your default format, without opening Clipiary.",
                value: appState.isRecordingGlobalAltPasteShortcut ? "Press keys..." : appState.settings.globalAltPasteShortcut.displayString,
                isRecording: appState.isRecordingGlobalAltPasteShortcut
            ) {
                appState.isRecordingGlobalAltPasteShortcut.toggle()
            }
        }
    }

    // MARK: - Components

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 2) {
                content()
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadii.card, style: .continuous)
                    .fill(theme.resolvedCardFill)
            )
            .overlay {
                let border = theme.resolvedCardBorder
                if border.isVisible {
                    RoundedRectangle(cornerRadius: theme.cornerRadii.card, style: .continuous)
                        .stroke(border.color, style: border.strokeStyle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingMetric<Control: View>(title: String, help: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let help {
                helpIcon(help)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func settingsToggleRow(title: String, help: String? = nil, isOn: Binding<Bool>, extra: AnyView? = nil) -> some View {
        HStack(spacing: 0) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            if let extra {
                extra
                    .padding(.leading, 6)
            }
            if let help {
                helpIcon(help)
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func shortcutRow(title: String, help: String? = nil, value: String, isRecording: Bool, onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                if let help {
                    helpIcon(help)
                }
            }

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadii.shortcutRecordField, style: .continuous)
                            .fill(isRecording ? theme.resolvedAccent.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    )

                Button(isRecording ? "Cancel" : "Record") {
                    onToggle()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func optionPicker(
        selection: Binding<Int>,
        options: [Int],
        label: @escaping (Int) -> String
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func helpIcon(_ text: String) -> some View {
        HelpIconView(text: text)
    }
}

private struct HelpIconView: View {
    let text: String
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingHelp, arrowEdge: .trailing) {
            Text(text)
                .font(.system(size: 11))
                .padding(10)
                .frame(width: 200)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TerminalBundleIDsConfigButton: View {
    @Binding var terminalBundleIDs: String
    @State private var isShowingConfig = false

    var body: some View {
        Button {
            isShowingConfig.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingConfig, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal/IDE bundle IDs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("com.apple.Terminal, ...", text: $terminalBundleIDs)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated list of app bundle identifiers.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(width: 300)
        }
        .onChange(of: isShowingConfig) { _, showing in
            if !showing {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

private struct IgnoredBundleIDsConfigButton: View {
    @Binding var ignoredBundleIDs: String
    @State private var isShowingConfig = false

    var body: some View {
        Button {
            isShowingConfig.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingConfig, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ignored app bundle IDs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("com.example.app, ...", text: $ignoredBundleIDs)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated list of app bundle identifiers to ignore.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(width: 300)
        }
        .onChange(of: isShowingConfig) { _, showing in
            if !showing {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

@MainActor
private final class SettingsPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector? = switch characters {
        case "v": #selector(NSText.paste(_:))
        case "c": #selector(NSText.copy(_:))
        case "x": #selector(NSText.cut(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": #selector(UndoManager.undo)
        default: nil
        }
        if let action {
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct ThemedSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SettingsView()
            .environment(\.theme, appState.themeManager.activeTheme)
            .preferredColorScheme(appState.themeManager.activeTheme.colorScheme)
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private(set) var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = ThemedSettingsView()
            .environment(AppState.shared)

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 610)

        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 610),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipiary Settings"
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.minSize = NSSize(width: 460, height: 340)
        window.maxSize = NSSize(width: 700, height: 800)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
