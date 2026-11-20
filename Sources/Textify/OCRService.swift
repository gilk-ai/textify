import Foundation
import Vision
import CoreGraphics

/// Result of an OCR pass.
struct OCRResult {
    let text: String
    /// True when some observations had low confidence — the image may be partially unreadable.
    let hasLowConfidence: Bool
}

enum OCRError: LocalizedError {
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .visionFailed(let msg): return "OCR failed: \(msg)"
        }
    }
}

/// On-device text recognition using Apple Vision. Nothing leaves the machine.
enum OCRService {
    private static let preferredLanguages = ["he-IL", "en-US"]
    private static let lowConfidenceThreshold: Float = 0.4

    /// Recognize text in an image. Runs Vision off the main thread.
    static func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try recognizeSync(image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func recognizeSync(_ image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Only ask for languages this OS revision supports; otherwise let Vision auto-detect.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let langs = preferredLanguages.filter { supported.contains($0) }
        if langs.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = langs
        }

        // Hebrew pass (Tesseract) runs in parallel with Vision when available.
        var hebrew: [Fragment] = []
        let group = DispatchGroup()
        if HebrewOCRService.isEnabled, HebrewOCRService.isAvailable {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                hebrew = (try? HebrewOCRService.recognizeHebrewLines(in: image)) ?? []
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            group.wait()
            if hebrew.isEmpty { throw OCRError.visionFailed(error.localizedDescription) }
        }
        group.wait()

        let observations = request.results ?? []
        var fragments: [Fragment] = []
        var lowConfidence = false
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let s = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            if candidate.confidence < lowConfidenceThreshold { lowConfidence = true }
            fragments.append(Fragment(text: s, box: obs.boundingBox))
        }

        if !hebrew.isEmpty {
            // Vision can't read Hebrew; drop whatever it guessed for those lines and use Tesseract's.
            fragments.removeAll { frag in hebrew.contains { TextLayout.overlapsVertically(frag.box, $0.box) && frag.box.intersects($0.box) } }
            fragments += hebrew
        }

        return OCRResult(text: TextLayout.assemble(fragments), hasLowConfidence: lowConfidence)
    }
}

/// A recognized piece of text with its normalized bounding box (Vision coords: origin bottom-left, 0…1).
struct Fragment {
    let text: String
    let box: CGRect
}

/// Turns unordered Vision fragments into reading-order text with line and paragraph breaks.
enum TextLayout {
    static func assemble(_ fragments: [Fragment]) -> String {
        guard !fragments.isEmpty else { return "" }

        // 1. Sort top → bottom (Vision y grows upward, so sort by maxY descending).
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }

        // 2. Group fragments whose vertical extents overlap substantially into the same line.
        var lines: [[Fragment]] = []
        for frag in sorted {
            if var last = lines.last, let ref = last.first, sameLine(ref.box, frag.box) {
                last.append(frag)
                lines[lines.count - 1] = last
            } else {
                lines.append([frag])
            }
        }

        // 3. Order fragments within each line: RTL lines right→left, others left→right.
        let lineInfos: [(text: String, box: CGRect)] = lines.map { line in
            let rtl = isPredominantlyRTL(line.map(\.text).joined())
            let ordered = line.sorted { rtl ? $0.box.minX > $1.box.minX : $0.box.minX < $1.box.minX }
            let box = line.dropFirst().reduce(line[0].box) { $0.union($1.box) }
            return (ordered.map(\.text).joined(separator: " "), box)
        }

        // 4. Insert blank lines where the vertical gap suggests a new paragraph.
        let heights = lineInfos.map { $0.box.height }.sorted()
        let typicalHeight = heights[heights.count / 2]
        var out = lineInfos[0].text
        for i in 1..<lineInfos.count {
            let gap = lineInfos[i - 1].box.minY - lineInfos[i].box.maxY
            out += gap > typicalHeight * 0.9 ? "\n\n" : "\n"
            out += lineInfos[i].text
        }
        return out
    }

    static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool { sameLine(a, b) }

    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    static func isPredominantlyRTL(_ s: String) -> Bool {
        var rtl = 0, ltr = 0
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: rtl += 1
            default:
                if scalar.properties.isAlphabetic { ltr += 1 }
            }
        }
        return rtl > ltr
    }
}
