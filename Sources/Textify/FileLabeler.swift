import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Produces a short, memorable label for a piece of extracted text, used in auto-saved file names.
///
/// 1. On macOS 26+ with Apple Intelligence available, asks the on-device system language model.
/// 2. Otherwise (or if the model fails / is slow), falls back to a local keyword heuristic.
/// Both paths run entirely on the Mac.
enum FileLabeler {
    static let maxLength = 40
    private static let modelTimeout: Duration = .seconds(4)

    static func label(for text: String) async -> String {
        if let l = await modelLabel(for: text).flatMap(sanitize), !l.isEmpty { return l }
        return sanitize(heuristicLabel(for: text)) ?? "Untitled"
    }

    // MARK: - On-device model

    private static func modelLabel(for text: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let snippet = String(text.prefix(1500))
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: """
                    You give short, memorable titles to text captured from screenshots, like a person \
                    naming a note. Write 2 to 5 natural words in Title Case that say what the text is about, \
                    including a distinctive name, number or subject when there is one. Use spaces, not \
                    underscores. Reply with the title only.
                    Examples: "Acme Invoice Due December", "Lemon Olive Oil Cake", "Monday Team Meeting Notes", \
                    "Flight Confirmation Tel Aviv".
                    """)
                return try? await session.respond(to: "Text:\n\(snippet)").content
            }
            group.addTask {
                try? await Task.sleep(for: modelTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #else
        return nil
        #endif
    }

    // MARK: - Heuristic fallback

    /// Picks the most frequent nouns / names (in order of first appearance); if the language isn't
    /// supported by the tagger (e.g. Hebrew), uses the first few words of the first line.
    static func heuristicLabel(for text: String) -> String {
        let sample = String(text.prefix(2000))
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sample

        var counts: [String: (count: Int, first: Int, display: String)] = [:]
        var index = 0
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            let word = String(sample[range])
            if (tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName),
               word.count >= 3 {
                let key = word.lowercased()
                let entry = counts[key] ?? (0, index, word)
                counts[key] = (entry.count + 1, entry.first, entry.display)
            }
            index += 1
            return true
        }

        let picked = counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.first < $1.first }
            .prefix(3)
            .sorted { $0.first < $1.first }
            .map { $0.display.prefix(1).uppercased() + $0.display.dropFirst() }
        if !picked.isEmpty { return picked.joined(separator: " ") }

        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.split(separator: " ").prefix(4).joined(separator: " ")
    }

    // MARK: - File-name safety

    /// Strips characters that are unsafe or awkward in file names and caps the length at a word boundary.
    static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let line = s.split(whereSeparator: \.isNewline).first { s = String(line) }
        if s.lowercased().hasPrefix("label:") { s = String(s.dropFirst(6)) }
        // Apostrophes are fine in file names ("Grandma's Cake"); quotes, path chars and commas are not.
        let banned = CharacterSet(charactersIn: "/\\:?*\"<>|`“”.#,;")
            .union(.controlCharacters)
        s = String(String.UnicodeScalarView(s.unicodeScalars.map { banned.contains($0) ? " " : $0 }))
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.split(separator: " ").joined(separator: " ")
        // Normalize SHOUTING to Title Case (keeps short all-caps tokens like "ID" or "USA" as-is).
        if s == s.uppercased(), s != s.lowercased() {
            s = s.split(separator: " ").map { w in
                w.count <= 3 ? String(w) : w.prefix(1) + w.dropFirst().lowercased()
            }.joined(separator: " ")
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -_,;!'‘’"))
        if s.count > maxLength {
            let cut = s.prefix(maxLength)
            s = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        }
        return s.isEmpty ? nil : s
    }
}
