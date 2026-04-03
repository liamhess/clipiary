import Foundation
import Observation

@MainActor
@Observable
final class ThemeManager {
    private(set) var availableThemes: [Theme] = []
    private(set) var activeTheme: Theme = .default

    private let fileManager: FileManager
    private let themesDirectoryURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()
    @ObservationIgnored private var directoryWatchSource: DispatchSourceFileSystemObject?

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let storageDirectory {
            themesDirectoryURL = storageDirectory.appending(path: "themes")
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            themesDirectoryURL = appSupport.appending(path: "Clipiary/themes")
        }
    }

    func ensureDefaultTheme() {
        try? fileManager.createDirectory(at: themesDirectoryURL, withIntermediateDirectories: true)
        for theme in Theme.builtInThemes {
            let url = themesDirectoryURL.appending(path: "\(theme.id).json")
            guard let data = try? encoder.encode(theme) else { continue }
            try? data.write(to: url, options: .atomic)
        }
    }

    func load() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: themesDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            availableThemes = [.default]
            resolveActiveTheme()
            return
        }

        var themes: [Theme] = []
        for url in contents where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let theme = try? decoder.decode(Theme.self, from: data) else {
                continue
            }
            themes.append(theme)
        }

        themes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if themes.isEmpty {
            themes = [.default]
        }
        availableThemes = themes
        resolveActiveTheme()
    }

    func selectTheme(id: String) {
        activeTheme = availableThemes.first { $0.id == id } ?? .default
    }

    /// Write a theme to disk and reload.
    func save(_ theme: Theme) throws {
        try fileManager.createDirectory(at: themesDirectoryURL, withIntermediateDirectories: true)
        let url = themesDirectoryURL.appending(path: "\(theme.id).json")
        let data = try encoder.encode(theme)
        try data.write(to: url, options: .atomic)
        load()
    }

    /// Duplicate any theme (including built-ins) with a new name and UUID-based id.
    @discardableResult
    func duplicate(_ theme: Theme, newName: String) throws -> Theme {
        var copy = theme
        copy.id = UUID().uuidString
        copy.name = newName
        try save(copy)
        return copy
    }

    /// Delete a custom theme. Throws if the theme is a built-in.
    func delete(id: String) throws {
        guard !Theme.builtInThemes.contains(where: { $0.id == id }) else {
            throw ThemeManagerError.cannotDeleteBuiltIn
        }
        let url = themesDirectoryURL.appending(path: "\(id).json")
        try fileManager.removeItem(at: url)
        load()
    }

    func startWatching() {
        stopWatching()
        try? fileManager.createDirectory(at: themesDirectoryURL, withIntermediateDirectories: true)

        let fd = open(themesDirectoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.load()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directoryWatchSource = source
    }

    func stopWatching() {
        directoryWatchSource?.cancel()
        directoryWatchSource = nil
    }

    private func resolveActiveTheme() {
        let currentID = activeTheme.id
        activeTheme = availableThemes.first { $0.id == currentID } ?? .default
    }
}

enum ThemeManagerError: Error, LocalizedError {
    case cannotDeleteBuiltIn

    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltIn: "Built-in themes cannot be deleted."
        }
    }
}
