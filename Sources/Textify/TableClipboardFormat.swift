import Foundation

/// Renders detected tables for the clipboard, so pasting into Excel, Numbers, Google Sheets,
/// Mail or Docs produces real cells. Plain-text apps keep receiving the regular OCR text.
enum TableClipboardFormat {
    /// HTML tables (with row/column spans). Multiple tables are separated by a blank line.
    static func html(_ tables: [ExtractedTable]) -> String {
        let body = tables.map { table -> String in
            let t = table.inReadingOrder()
            let byRow = Dictionary(grouping: t.cells, by: \.row)
            let rows = (0..<t.rowCount).map { r -> String in
                let cells = (byRow[r] ?? []).sorted { $0.column < $1.column }.map { c -> String in
                    var attrs = ""
                    if c.rowSpan > 1 { attrs += " rowspan=\"\(c.rowSpan)\"" }
                    if c.columnSpan > 1 { attrs += " colspan=\"\(c.columnSpan)\"" }
                    let text = escape(c.text).replacingOccurrences(of: "\n", with: "<br>")
                    return "<td\(attrs)>\(text)</td>"
                }.joined()
                return "<tr>\(cells)</tr>"
            }.joined()
            let dir = t.isRightToLeft ? " dir=\"rtl\"" : ""
            return "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\"\(dir)>\(rows)</table>"
        }.joined(separator: "<br>")
        return "<html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    /// Tab-separated values. Merged cells occupy their first position; covered positions stay empty.
    static func tsv(_ tables: [ExtractedTable]) -> String {
        tables.map { table -> String in
            let t = table.inReadingOrder()
            var grid = Array(repeating: Array(repeating: "", count: t.columnCount), count: t.rowCount)
            for c in t.cells where c.row < t.rowCount && c.column < t.columnCount {
                // Tabs/newlines inside a cell would break the grid.
                grid[c.row][c.column] = c.text.replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
            }
            return grid.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
