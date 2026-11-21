import AppKit

enum ClipboardError: LocalizedError {
    case noImage
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noImage: return "No image on the clipboard. Take a screenshot with ⌃⇧⌘4, then press ⌘V."
        case .writeFailed: return "Couldn't update the clipboard. Use the Copy button."
        }
    }
}

/// Reads images from and writes text to the general pasteboard.
final class ClipboardManager {
    static let shared = ClipboardManager()
    private let pb = NSPasteboard.general

    /// changeCount of the pasteboard right after TEXTIFY wrote to it.
    private(set) var lastOwnWriteChangeCount: Int = -1

    var changeCount: Int { pb.changeCount }

    /// True if the clipboard still holds the text TEXTIFY put there.
    var clipboardIsOurOwnText: Bool { pb.changeCount == lastOwnWriteChangeCount }

    /// Extracts an image from the clipboard. Handles screenshots (PNG/TIFF data),
    /// browser "Copy Image", and image files copied in Finder.
    func readImage() throws -> CGImage {
        // 1. Files copied from Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            return try ImageLoader.load(url: url)
        }
        // 2. Raw image data (screenshots, browsers).
        for type in [NSPasteboard.PasteboardType.png, .tiff,
                     NSPasteboard.PasteboardType("public.jpeg"),
                     NSPasteboard.PasteboardType("public.heic")] {
            if let data = pb.data(forType: type), let img = try? ImageLoader.load(data: data) {
                return img
            }
        }
        // 3. Anything else NSImage can make sense of.
        if let image = NSImage(pasteboard: pb) {
            return try ImageLoader.cgImage(from: image)
        }
        throw ClipboardError.noImage
    }

    static let tsvType = NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")

    /// Replaces the clipboard contents with `text`. Throws if the write did not stick.
    /// With `tables`, also offers HTML + tab-separated versions, so spreadsheets and rich-text apps
    /// paste real cells while plain-text apps still get `text`.
    func writeText(_ text: String, tables: [ExtractedTable] = []) throws {
        pb.clearContents()
        var ok = pb.setString(text, forType: .string)
        if ok, !tables.isEmpty {
            ok = pb.setString(TableClipboardFormat.html(tables), forType: .html)
                && pb.setString(TableClipboardFormat.tsv(tables), forType: Self.tsvType)
        }
        guard ok, pb.string(forType: .string) == text else { throw ClipboardError.writeFailed }
        lastOwnWriteChangeCount = pb.changeCount
    }
}
