import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Apple's on-device OCR engines (Vision, VisionKit Live Text) do not support Hebrew.
/// When the open-source Tesseract engine is installed locally (`brew install tesseract tesseract-lang`),
/// TEXTIFY runs it alongside Vision and uses it for lines that contain Hebrew.
/// Tesseract runs as a local process; the image is piped via stdin — nothing is written to disk
/// and nothing leaves the machine.
enum HebrewOCRService {
    private static let binaryCandidates = ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract"]

    static var tesseractPath: String? {
        binaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// True when Tesseract and its Hebrew model are installed.
    static var isAvailable: Bool {
        guard let bin = tesseractPath else { return false }
        let prefix = URL(fileURLWithPath: bin).deletingLastPathComponent().deletingLastPathComponent()
        let model = prefix.appendingPathComponent("share/tessdata/heb.traineddata").path
        return FileManager.default.fileExists(atPath: model)
    }

    static let enabledKey = "hebrewOCREnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Returns Hebrew-containing lines as fragments in Vision's normalized coordinate space.
    static func recognizeHebrewLines(in image: CGImage) throws -> [Fragment] {
        guard let bin = tesseractPath else { return [] }
        guard let png = pngData(image) else { return [] }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        // --psm 3: automatic page segmentation. heb+eng so mixed lines keep their English words.
        proc.arguments = ["stdin", "stdout", "-l", "heb+eng", "--psm", "3", "tsv"]
        let input = Pipe(), output = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        // Write and read concurrently so large images can't deadlock the pipes.
        DispatchQueue.global().async {
            input.fileHandleForWriting.write(png)
            try? input.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, let tsv = String(data: data, encoding: .utf8) else { return [] }
        return parse(tsv: tsv, width: CGFloat(image.width), height: CGFloat(image.height))
    }

    /// Parses Tesseract TSV (word level) into line fragments, keeping only lines with Hebrew letters.
    static func parse(tsv: String, width: CGFloat, height: CGFloat) -> [Fragment] {
        struct Line { var words: [String] = []; var rect: CGRect = .null }
        var lines: [String: Line] = [:]
        var order: [String] = []

        for row in tsv.split(separator: "\n").dropFirst() {
            let c = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count >= 12, c[0] == "5",
                  let conf = Double(c[10]), conf > 30,
                  let l = Double(c[6]), let t = Double(c[7]), let w = Double(c[8]), let h = Double(c[9])
            else { continue }
            // Strip invisible bidi control marks Tesseract sometimes emits (LRM/RLM/embeddings/isolates).
            let word = String(String.UnicodeScalarView(c[11].unicodeScalars.filter {
                !(0x200E...0x200F).contains($0.value) && !(0x202A...0x202E).contains($0.value)
                    && !(0x2066...0x2069).contains($0.value)
            })).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            let key = "\(c[2])-\(c[3])-\(c[4])" // block-paragraph-line
            if lines[key] == nil { order.append(key); lines[key] = Line() }
            lines[key]!.words.append(word)
            lines[key]!.rect = lines[key]!.rect.union(CGRect(x: l, y: t, width: w, height: h))
        }

        return order.compactMap { key in
            guard let line = lines[key] else { return nil }
            let text = line.words.joined(separator: " ")
            guard containsHebrew(text) else { return nil }
            let r = line.rect
            // Pixel coords (origin top-left) → Vision normalized coords (origin bottom-left).
            let box = CGRect(x: r.minX / width, y: 1 - r.maxY / height,
                             width: r.width / width, height: r.height / height)
            return Fragment(text: text, box: box)
        }
    }

    static func containsHebrew(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) || (0xFB1D...0xFB4F).contains($0.value) }
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
