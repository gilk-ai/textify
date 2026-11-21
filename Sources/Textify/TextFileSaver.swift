import Foundation
import CoreGraphics

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

    /// Writes `text` according to the current settings. Returns the main file written to.
    ///
    /// When `tables` is non-empty the image held a clearly structured table:
    /// - New-file mode writes a single .xlsx (one sheet per table + a "Full Text" sheet) instead of .txt.
    /// - Append mode still appends the text to the log, and writes the .xlsx next to it.
    @discardableResult
    static func save(_ text: String, label: String? = nil, tables: [ExtractedTable] = [],
                     to folder: URL = folder, mode: Mode = mode, date: Date = Date()) throws -> URL {
        let label = label.flatMap(FileLabeler.sanitize)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var base = "TEXTIFY \(stamp(date, "yyyy-MM-dd 'at' HH.mm.ss"))"
        if let label { base += " - \(label)" }

        var spreadsheet: URL?
        if !tables.isEmpty {
            let url = uniqueURL(in: folder, base: base, ext: "xlsx")
            try XLSXWriter.write(tables: tables, fullText: text, to: url)
            spreadsheet = url
        }

        switch mode {
        case .newFile:
            if let spreadsheet { return spreadsheet }
            let url = uniqueURL(in: folder, base: base, ext: "txt")
            try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url

        case .append:
            let url = folder.appendingPathComponent(appendFileName)
            // One shared file, so the label goes into each entry's header instead of the file name.
            let header = [stamp(date, "yyyy-MM-dd HH:mm:ss"), label].compactMap { $0 }.joined(separator: " · ")
            let note = spreadsheet.map { "[Table saved as \($0.lastPathComponent)]\n" } ?? ""
            let entry = "── \(header) ──\n\(note)\(text)\n\n"
            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try entry.write(to: url, atomically: true, encoding: .utf8)
            }
            return spreadsheet ?? url
        }
    }

    /// Everything a save needs besides the text, computed concurrently: the file label and,
    /// if enabled and supported, any clearly structured tables in the image.
    static func prepare(text: String, image: CGImage?) async -> (label: String, tables: [ExtractedTable]) {
        async let label = FileLabeler.label(for: text)
        async let tables: [ExtractedTable] = {
            guard let image, TableExtractor.isEnabled, TableExtractor.isSupported else { return [] }
            return await TableExtractor.tables(in: image, containsHebrew: HebrewOCRService.containsHebrew(text))
        }()
        return await (label, tables)
    }

    private static func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)")
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
