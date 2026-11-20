import AppKit
import UniformTypeIdentifiers
import ImageIO
import CryptoKit

enum ImageLoadError: LocalizedError {
    case unsupportedFormat(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported format\(ext.isEmpty ? "" : " (.\(ext))"). Use PNG, JPG, HEIC or TIFF."
        case .unreadable:
            return "Couldn't read that image."
        }
    }
}

/// Loads images from files, raw data or NSImage into CGImage for Vision.
enum ImageLoader {
    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .bmp, .gif]

    static func isSupported(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    static func load(url: URL) throws -> CGImage {
        guard isSupported(url: url) else {
            throw ImageLoadError.unsupportedFormat(url.pathExtension)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageLoadError.unreadable
        }
        return img
    }

    static func load(data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageLoadError.unreadable
        }
        return img
    }

    static func cgImage(from nsImage: NSImage) throws -> CGImage {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) { return cg }
        if let tiff = nsImage.tiffRepresentation { return try load(data: tiff) }
        throw ImageLoadError.unreadable
    }

    /// Cheap fingerprint used to avoid re-processing the same image.
    static func fingerprint(_ image: CGImage) -> String {
        guard let data = image.dataProvider?.data as Data? else {
            return "\(image.width)x\(image.height)"
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
