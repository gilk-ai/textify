import Foundation
import Vision
import CoreGraphics

/// A table recovered from an image: a grid of cells, some of which may span several rows/columns.
struct ExtractedTable {
    struct Cell {
        let row: Int, column: Int
        let rowSpan: Int, columnSpan: Int
        var text: String
    }
    let rowCount: Int
    let columnCount: Int
    var cells: [Cell]

    /// True when most text in the table is right-to-left (Hebrew/Arabic) — the sheet is then shown RTL.
    var isRightToLeft: Bool {
        TextLayout.isPredominantlyRTL(cells.map(\.text).joined(separator: " "))
    }
}

/// Detects clearly structured tables using Vision's document understanding (macOS 26+, on-device).
enum TableExtractor {
    static let enabledKey = "saveTablesAsExcel"

    /// User setting: save detected tables as .xlsx (on by default; only matters when auto-save is on).
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Returns every clearly structured table in the image (at least 2×2 with real content),
    /// or an empty array. `containsHebrew` should reflect the OCR text: Vision can't read Hebrew,
    /// so Hebrew tables keep Vision's grid but take each cell's words from Tesseract.
    static func tables(in image: CGImage, containsHebrew: Bool) async -> [ExtractedTable] {
        guard #available(macOS 26, *) else { return [] }
        guard let observations = try? await RecognizeDocumentsRequest().perform(on: image) else { return [] }

        var hebrewWords: [Fragment]?
        if containsHebrew, HebrewOCRService.isEnabled, HebrewOCRService.isAvailable {
            hebrewWords = try? HebrewOCRService.recognizeWords(in: image)
        }

        var result: [ExtractedTable] = []
        for observation in observations {
            for table in observation.document.tables {
                var cells: [ExtractedTable.Cell] = []
                for cell in table.rows.flatMap({ $0 }) {
                    var text = cell.content.text.transcript
                    if let words = hebrewWords {
                        text = wordsInside(cell.content.boundingRegion.boundingBox.cgRect, from: words)
                    }
                    cells.append(.init(row: cell.rowRange.lowerBound, column: cell.columnRange.lowerBound,
                                       rowSpan: cell.rowRange.count, columnSpan: cell.columnRange.count,
                                       text: clean(text)))
                }
                let t = ExtractedTable(rowCount: table.rows.count, columnCount: table.columns.count, cells: cells)
                if isClearlyStructured(t) { result.append(t) }
            }
        }
        return result
    }

    /// Guards against "tables" that are really just a couple of stray aligned words.
    static func isClearlyStructured(_ t: ExtractedTable) -> Bool {
        guard t.rowCount >= 2, t.columnCount >= 2 else { return false }
        let filled = t.cells.filter { !$0.text.isEmpty }.count
        return filled >= 4 && Double(filled) >= 0.5 * Double(t.cells.count)
    }

    /// Joins the Tesseract words whose centers fall inside a cell, in reading order
    /// (top→bottom, then right→left for RTL lines / left→right otherwise).
    private static func wordsInside(_ box: CGRect, from words: [Fragment]) -> String {
        let inside = words.filter { box.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
        return TextLayout.assemble(inside).replacingOccurrences(of: "\n\n", with: "\n")
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
