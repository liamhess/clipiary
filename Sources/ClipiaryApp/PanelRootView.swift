import AppKit
import SwiftUI

struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredItemID: HistoryItem.ID?
    @State private var showHistory = true
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.black.opacity(0.04))
            controls
            footer
        }
        .frame(width: 360, height: 460)
        .background(panelBackground)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Clipiary")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                iconToggle(
                    systemName: "doc.on.clipboard",
                    isOn: Binding(
                        get: { appState.settings.isClipboardMonitoringEnabled },
                        set: { appState.settings.isClipboardMonitoringEnabled = $0 }
                    ),
                    help: "Clipboard monitoring"
                )
                iconToggle(
                    systemName: "cursorarrow.rays",
                    isOn: Binding(
                        get: { appState.settings.isAutoSelectEnabled },
                        set: { appState.settings.isAutoSelectEnabled = $0 }
                    ),
                    help: "Autoselect"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !appState.permissionManager.isTrusted {
                    Button("Grant Accessibility Access") {
                        appState.refreshAutoSelectPermissions()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                }

                Toggle("Show recent item in menu bar", isOn: Binding(
                    get: { appState.settings.showRecentItemInStatusBar },
                    set: { appState.settings.showRecentItemInStatusBar = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

                HStack(spacing: 12) {
                    Stepper("Min \(appState.settings.minimumSelectionLength)", value: Binding(
                        get: { appState.settings.minimumSelectionLength },
                        set: { appState.settings.minimumSelectionLength = max(1, $0) }
                    ), in: 1...10)
                    Stepper("\(appState.settings.autoSelectCooldownMilliseconds) ms", value: Binding(
                        get: { appState.settings.autoSelectCooldownMilliseconds },
                        set: { appState.settings.autoSelectCooldownMilliseconds = min(max(100, $0), 2000) }
                    ), in: 100...2000, step: 50)
                }
                .font(.system(size: 11))

                historySection
            }
            .padding(12)
        }
    }

    private var historySection: some View {
        DisclosureGroup(isExpanded: $showHistory) {
            VStack(spacing: 8) {
                searchField
                if filteredHistoryItems.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHistoryItems.prefix(40)) { item in
                            row(for: item)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(filteredHistoryItems.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.black.opacity(0.04))
            HStack {
                accessibilityStatus
                Spacer()
                Button("Clear") {
                    appState.history.clearUnpinned()
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
                Text("\(appState.history.items.count) items")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
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
            TextField("Search clipboard history", text: Binding(
                get: { appState.history.searchQuery },
                set: { appState.history.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(buttonFill)
        )
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
                    appState.history.togglePin(item)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)

                Button {
                    appState.history.delete(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(item.appName)
                Text("·")
                Text(item.createdAt, style: .time)
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
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No clipboard history yet")
                .font(.system(size: 13, weight: .medium))
            Text("Copy something, or enable autoselect to capture highlighted text.")
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
            .fill(hoveredItemID == item.id ? buttonFill : Color.clear)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private func iconToggle(systemName: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: isOn.wrappedValue ? "\(systemName).fill" : systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
        .background(Circle().fill(buttonFill))
        .help(help)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var buttonFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }

    private var filteredHistoryItems: [HistoryItem] {
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
}
