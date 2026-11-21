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
        guard let tsv = try runTesseract(image) else { return [] }
        return parse(tsv: tsv, width: CGFloat(image.width), height: CGFloat(image.height))
    }

    /// Every recognized word (Hebrew or not) with its own box, in Tesseract's reading order.
    /// Used to fill table cells when a table contains Hebrew.
    static func recognizeWords(in image: CGImage) throws -> [Fragment] {
        guard let tsv = try runTesseract(image) else { return [] }
        return words(tsv: tsv, width: CGFloat(image.width), height: CGFloat(image.height)).map(\.fragment)
    }

    private static func runTesseract(_ image: CGImage) throws -> String? {
        guard let bin = tesseractPath, let png = pngData(image) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["stdin", "stdout", "-l", "heb+eng", "--psm", "3", "tsv"]
        let input = Pipe(), output = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        DispatchQueue.global().async {
            input.fileHandleForWriting.write(png)
            try? input.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Word rows from Tesseract TSV, with boxes converted to Vision's normalized coordinates.
    private static func words(tsv: String, width: CGFloat, height: CGFloat) -> [(fragment: Fragment, lineKey: String)] {
        var out: [(Fragment, String)] = []
        for row in tsv.split(separator: "\n").dropFirst() {
            let c = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count >= 12, c[0] == "5",
                  let conf = Double(c[10]), conf > 30,
                  let l = Double(c[6]), let t = Double(c[7]), let w = Double(c[8]), let h = Double(c[9])
            else { continue }
            let word = stripBidiMarks(String(c[11])).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            // Pixel coords (origin top-left) → Vision normalized coords (origin bottom-left).
            let box = CGRect(x: l / width, y: 1 - (t + h) / height, width: w / width, height: h / height)
            out.append((Fragment(text: word, box: box), "\(c[2])-\(c[3])-\(c[4])"))
        }
        return out
    }

    /// Removes invisible bidi control marks Tesseract sometimes emits (LRM/RLM/embeddings/isolates).
    private static func stripBidiMarks(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter {
            !(0x200E...0x200F).contains($0.value) && !(0x202A...0x202E).contains($0.value)
                && !(0x2066...0x2069).contains($0.value)
        }))
    }

    /// Parses Tesseract TSV into line fragments, keeping only lines with Hebrew letters.
    static func parse(tsv: String, width: CGFloat, height: CGFloat) -> [Fragment] {
        var lines: [String: (words: [String], box: CGRect)] = [:]
        var order: [String] = []
        for (frag, key) in words(tsv: tsv, width: width, height: height) {
            if lines[key] == nil { order.append(key); lines[key] = ([], .null) }
            lines[key]!.words.append(frag.text)
            lines[key]!.box = lines[key]!.box.union(frag.box)
        }
        return order.compactMap { key in
            guard let line = lines[key] else { return nil }
            let text = line.words.joined(separator: " ")
            return containsHebrew(text) ? Fragment(text: text, box: line.box) : nil
        }
    }

    /// Fraction of letters that are Hebrew (0…1).
    static func hebrewShare(_ s: String) -> Double {
        var hebrew = 0, letters = 0
        for scalar in s.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if (0x0590...0x05FF).contains(scalar.value) || (0xFB1D...0xFB4F).contains(scalar.value) { hebrew += 1 }
        }
        return letters == 0 ? 0 : Double(hebrew) / Double(letters)
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
