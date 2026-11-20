import Foundation

/// Optional, opt-in saving of extracted text to disk.
enum TextFileSaver {
    enum Mode: String, CaseIterable, Identifiable {
        case newFile, append
        var id: String { rawValue }
        var label: String { self == .newFile ? "New file each time" : "Append to one file" }
    }

    static let appendFileName = "TEXTIFY Log.txt"

    private enum Keys {
        static let enabled = "autoSaveEnabled"
        static let folder = "autoSaveFolder"
        static let mode = "autoSaveMode"
    }

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) } // off by default
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/TEXTIFY", isDirectory: true)
    }

    static var folder: URL {
        get { defaults.string(forKey: Keys.folder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder }
        set { defaults.set(newValue.path, forKey: Keys.folder) }
    }

    static var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .newFile }
        set { defaults.set(newValue.rawValue, forKey: Keys.mode) }
    }

    /// Writes `text` according to the current settings. Returns the file written to.
    @discardableResult
    static func save(_ text: String, label: String? = nil, to folder: URL = folder, mode: Mode = mode,
                     date: Date = Date()) throws -> URL {
        let label = label.flatMap(FileLabeler.sanitize)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        switch mode {
        case .newFile:
            var base = "TEXTIFY \(stamp(date, "yyyy-MM-dd 'at' HH.mm.ss"))"
            if let label { base += " - \(label)" }
            let url = uniqueURL(in: folder, base: base)
            try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url

        case .append:
            let url = folder.appendingPathComponent(appendFileName)
            // One shared file, so the label goes into each entry's header instead of the file name.
            let header = [stamp(date, "yyyy-MM-dd HH:mm:ss"), label].compactMap { $0 }.joined(separator: " · ")
            let entry = "── \(header) ──\n\(text)\n\n"
            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try entry.write(to: url, atomically: true, encoding: .utf8)
            }
            return url
        }
    }

    private static func uniqueURL(in folder: URL, base: String) -> URL {
        var url = folder.appendingPathComponent("\(base).txt")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).txt")
            n += 1
        }
        return url
    }

    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}
