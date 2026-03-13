import AppKit
import SwiftUI

struct PanelRootView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItemID: HistoryItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            historyList
            Divider()
            footer
        }
        .frame(width: 420, height: 540)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clipiary")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Toggle("Autoselect", isOn: Binding(
                    get: { appState.settings.isAutoSelectEnabled },
                    set: { appState.settings.isAutoSelectEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            TextField("Search clipboard history", text: Binding(
                get: { appState.history.searchQuery },
                set: { appState.history.searchQuery = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Toggle("Clipboard", isOn: Binding(
                    get: { appState.settings.isClipboardMonitoringEnabled },
                    set: { appState.settings.isClipboardMonitoringEnabled = $0 }
                ))
                Toggle("Show recent item in menu bar", isOn: Binding(
                    get: { appState.settings.showRecentItemInStatusBar },
                    set: { appState.settings.showRecentItemInStatusBar = $0 }
                ))
            }
            .font(.caption)
        }
        .padding(16)
    }

    private var historyList: some View {
        List(selection: $selectedItemID) {
            ForEach(appState.history.filteredItems) { item in
                Button {
                    appState.restore(item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.displayText.isEmpty ? "Untitled" : item.displayText)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                            Spacer()
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(item.appName)
                            Text(item.source.rawValue)
                            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(item.isPinned ? "Unpin" : "Pin") {
                        appState.history.togglePin(item)
                    }
                    Button("Copy Back to Clipboard") {
                        appState.restore(item)
                    }
                    Button("Delete") {
                        appState.history.delete(item)
                    }
                }
                .tag(item.id)
            }
        }
        .listStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                accessibilityStatus
                Spacer()
                Button("Grant Accessibility Access") {
                    appState.refreshAutoSelectPermissions()
                }
                .buttonStyle(.link)
            }

            HStack(spacing: 12) {
                Stepper("Min selection: \(appState.settings.minimumSelectionLength)", value: Binding(
                    get: { appState.settings.minimumSelectionLength },
                    set: { appState.settings.minimumSelectionLength = max(1, $0) }
                ), in: 1...10)

                Stepper("Cooldown: \(appState.settings.autoSelectCooldownMilliseconds) ms", value: Binding(
                    get: { appState.settings.autoSelectCooldownMilliseconds },
                    set: { appState.settings.autoSelectCooldownMilliseconds = min(max(100, $0), 2000) }
                ), in: 100...2000, step: 50)
            }
            .font(.caption)

            HStack {
                Button("Clear Unpinned") {
                    appState.history.clearUnpinned()
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
                Text("\(appState.history.items.count) items")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(16)
    }

    private var accessibilityStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.permissionManager.isTrusted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(appState.permissionManager.isTrusted ? "Accessibility granted" : "Accessibility required for autoselect")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
