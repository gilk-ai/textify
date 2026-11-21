import Foundation

/// Writes tables to a minimal but standard .xlsx (Office Open XML) workbook — no dependencies.
///
/// - One sheet per table ("Table 1", "Table 2", …) plus a "Full Text" sheet with every OCR line,
///   so nothing outside the table is lost.
/// - Merged cells are preserved. Numeric cells become real numbers with a matching display format
///   (e.g. "1,299.00" → 1299 shown as #,##0.00; "12%" → 0.12 shown as 0%), so they can be summed.
/// - A text-only first row is treated as a header: bold and frozen.
/// - Hebrew/RTL tables get a right-to-left sheet.
enum XLSXWriter {
    static func write(tables: [ExtractedTable], fullText: String, to url: URL) throws {
        var formats = NumberFormats()
        var sheets: [(name: String, xml: String)] = tables.enumerated().map { i, t in
            ("Table \(i + 1)", sheetXML(for: t, formats: &formats))
        }
        sheets.append(("Full Text", textSheetXML(fullText)))

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes(sheetCount: sheets.count))
        zip.add("_rels/.rels", rootRels)
        zip.add("xl/workbook.xml", workbook(names: sheets.map(\.name)))
        zip.add("xl/_rels/workbook.xml.rels", workbookRels(sheetCount: sheets.count))
        zip.add("xl/styles.xml", styles(formats))
        for (i, sheet) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(i + 1).xml", sheet.xml)
        }
        try zip.data().write(to: url, options: .atomic)
    }

    // MARK: - Sheets

    /// Fixed style indexes into `cellXfs`; number formats follow from index 3 (see `NumberFormats`).
    private enum TextStyle: Int { case text = 0, header = 1, wrap = 2 }

    /// Collects the distinct number formats used, so each gets its own cell style.
    struct NumberFormats {
        private(set) var codes: [String] = []
        /// Style index (cellXfs) for a format code.
        mutating func style(for code: String) -> Int {
            if let i = codes.firstIndex(of: code) { return 3 + i }
            codes.append(code)
            return 2 + codes.count
        }
    }

    private static func sheetXML(for table: ExtractedTable, formats: inout NumberFormats) -> String {
        // Vision numbers columns left→right as they appear in the image. A right-to-left sheet shows
        // column A on the right, so mirror RTL tables to keep the same visual layout as the image.
        var table = table
        if table.isRightToLeft {
            table.cells = table.cells.map { c in
                var m = c
                m = .init(row: c.row, column: table.columnCount - c.column - c.columnSpan,
                          rowSpan: c.rowSpan, columnSpan: c.columnSpan, text: c.text)
                return m
            }
        }
        let grid = Dictionary(table.cells.map { ("\($0.row),\($0.column)", $0) }, uniquingKeysWith: { a, _ in a })
        let headerRow = table.cells.filter { $0.row == 0 }
        let hasHeader = table.rowCount > 1 && !headerRow.isEmpty
            && headerRow.allSatisfy { parseNumber($0.text) == nil }

        var rowsXML = ""
        for r in 0..<table.rowCount {
            var cellsXML = ""
            for c in 0..<table.columnCount {
                guard let cell = grid["\(r),\(c)"], !cell.text.isEmpty else { continue }
                let ref = cellRef(row: r, column: c)
                if r > 0 || !hasHeader, let (value, code) = parseNumber(cell.text) {
                    cellsXML += #"<c r="\#(ref)" s="\#(formats.style(for: code))"><v>\#(value)</v></c>"#
                } else {
                    let style: TextStyle = (r == 0 && hasHeader) ? .header : (cell.text.contains("\n") ? .wrap : .text)
                    cellsXML += #"<c r="\#(ref)" s="\#(style.rawValue)" t="inlineStr"><is><t xml:space="preserve">\#(escape(cell.text))</t></is></c>"#
                }
            }
            rowsXML += #"<row r="\#(r + 1)">\#(cellsXML)</row>"#
        }

        // Column widths from the longest line in each column (single-column cells only).
        var widths = [Int](repeating: 8, count: table.columnCount)
        for cell in table.cells where cell.columnSpan == 1 {
            let longest = cell.text.split(separator: "\n").map(\.count).max() ?? 0
            widths[cell.column] = max(widths[cell.column], min(longest + 3, 60))
        }
        let cols = widths.enumerated().map { i, w in
            #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(w)" customWidth="1"/>"#
        }.joined()

        let merges = table.cells.filter { $0.rowSpan > 1 || $0.columnSpan > 1 }.map { cell in
            let from = cellRef(row: cell.row, column: cell.column)
            let to = cellRef(row: cell.row + cell.rowSpan - 1, column: cell.column + cell.columnSpan - 1)
            return #"<mergeCell ref="\#(from):\#(to)"/>"#
        }
        let mergeXML = merges.isEmpty ? "" : #"<mergeCells count="\#(merges.count)">\#(merges.joined())</mergeCells>"#

        let rtl = table.isRightToLeft ? #" rightToLeft="1""# : ""
        let pane = hasHeader
            ? #"<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>"#
            : ""
        return xmlHeader + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
            + #"<sheetViews><sheetView workbookViewId="0"\#(rtl)>\#(pane)</sheetView></sheetViews>"#
            + "<cols>\(cols)</cols><sheetData>\(rowsXML)</sheetData>\(mergeXML)</worksheet>"
    }

    private static func textSheetXML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let rtl = TextLayout.isPredominantlyRTL(text) ? #" rightToLeft="1""# : ""
        let rows = lines.enumerated().map { i, line -> String in
            guard !line.isEmpty else { return #"<row r="\#(i + 1)"/>"# }
            return #"<row r="\#(i + 1)"><c r="A\#(i + 1)" t="inlineStr"><is><t xml:space="preserve">\#(escape(line))</t></is></c></row>"#
        }.joined()
        return xmlHeader + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
            + #"<sheetViews><sheetView workbookViewId="0"\#(rtl)/></sheetViews>"#
            + #"<cols><col min="1" max="1" width="100" customWidth="1"/></cols>"#
            + "<sheetData>\(rows)</sheetData></worksheet>"
    }

    // MARK: - Numbers

    /// Recognizes plain numbers as they appear in tables and returns the value plus an Excel number
    /// format that reproduces the original text exactly ("1,299.00" → #,##0.00, "8.5%" → 0.0%).
    /// Anything else (currency symbols, dates, codes, leading zeros) stays text.
    static func parseNumber(_ raw: String) -> (value: String, format: String)? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        let percent = s.hasSuffix("%")
        if percent { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        // Optional sign, digits with valid thousands groups or plain digits, optional decimals.
        guard s.range(of: #"^-?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        // Leading zeros (ZIP codes, IDs like 0512) must stay text to match the table exactly.
        let digits = s.hasPrefix("-") ? String(s.dropFirst()) : s
        if digits.count > 1, digits.hasPrefix("0"), !digits.hasPrefix("0.") { return nil }

        guard var value = Double(s.replacingOccurrences(of: ",", with: "")) else { return nil }
        if percent { value /= 100 }

        let decimals = s.split(separator: ".").dropFirst().first?.count ?? 0
        var code = s.contains(",") ? "#,##0" : "0"
        if decimals > 0 { code += "." + String(repeating: "0", count: decimals) }
        if percent { code += "%" }
        // %.15g avoids binary-float noise like 0.12000000000000001.
        return (String(format: "%.15g", value), code)
    }

    // MARK: - Helpers

    static func cellRef(row: Int, column: Int) -> String {
        var n = column + 1, letters = ""
        while n > 0 {
            let r = (n - 1) % 26
            letters = String(UnicodeScalar(65 + r)!) + letters
            n = (n - 1) / 26
        }
        return "\(letters)\(row + 1)"
    }

    /// XML-escapes text and drops characters XML 1.0 forbids.
    static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n", "\t": out.unicodeScalars.append(scalar)
            default:
                if scalar.value >= 0x20 && scalar.value != 0xFFFE && scalar.value != 0xFFFF {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    private static let xmlHeader = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"

    private static func contentTypes(sheetCount: Int) -> String {
        let sheets = (1...sheetCount).map {
            #"<Override PartName="/xl/worksheets/sheet\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        return xmlHeader + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
            + #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
            + sheets + "</Types>"
    }

    private static let rootRels = xmlHeader
        + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"#
        + "</Relationships>"

    private static func workbook(names: [String]) -> String {
        let sheets = names.enumerated().map { i, name in
            #"<sheet name="\#(escape(name))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
        }.joined()
        return xmlHeader + #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#
            + "<sheets>\(sheets)</sheets></workbook>"
    }

    private static func workbookRels(sheetCount: Int) -> String {
        var rels = (1...sheetCount).map {
            #"<Relationship Id="rId\#($0)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#($0).xml"/>"#
        }
        rels.append(#"<Relationship Id="rId\#(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#)
        return xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
            + rels.joined() + "</Relationships>"
    }

    /// Built-in Excel number formats; anything else gets a custom id from 164.
    private static let builtinFormats = ["0": 1, "0.00": 2, "#,##0": 3, "#,##0.00": 4, "0%": 9, "0.00%": 10]

    /// cellXfs: 0 text, 1 header (bold, tinted, underlined), 2 wrapped text, 3… one per number format.
    private static func styles(_ formats: NumberFormats) -> String {
        var customFmts: [String] = []
        var numberXfs = ""
        for code in formats.codes {
            let id: Int
            if let builtin = builtinFormats[code] {
                id = builtin
            } else {
                id = 164 + customFmts.count
                customFmts.append(#"<numFmt numFmtId="\#(id)" formatCode="\#(escape(code))"/>"#)
            }
            numberXfs += #"<xf numFmtId="\#(id)" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>"#
        }
        let numFmts = customFmts.isEmpty ? "" : #"<numFmts count="\#(customFmts.count)">\#(customFmts.joined())</numFmts>"#
        return xmlHeader
            + #"<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
            + numFmts
            + #"<fonts count="2"><font><sz val="12"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts>"#
            + #"<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#
            + #"<fill><patternFill patternType="solid"><fgColor rgb="FFE8F5D0"/><bgColor indexed="64"/></patternFill></fill></fills>"#
            + #"<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>"#
            + #"<border><left/><right/><top/><bottom style="thin"><color rgb="FF8AAF3A"/></bottom><diagonal/></border></borders>"#
            + #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
            + #"<cellXfs count="\#(3 + formats.codes.count)">"#
            + #"<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>"#
            + #"<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>"#
            + #"<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>"#
            + numberXfs
            + "</cellXfs>"
            + #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
            + "</styleSheet>"
    }
}

/// Minimal ZIP archive writer (stored entries, no compression) — enough for .xlsx files.
struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ path: String, _ content: String) {
        let data = Data(content.utf8)
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(body.count)
        let (time, date) = dosDateTime(Date())

        var local = Data()
        local.le32(0x0403_4b50); local.le16(20); local.le16(0x0800); local.le16(0) // sig, version, UTF-8 flag, stored
        local.le16(time); local.le16(date); local.le32(crc)
        local.le32(UInt32(data.count)); local.le32(UInt32(data.count))
        local.le16(UInt16(name.count)); local.le16(0)
        body += local + name + data

        var entry = Data()
        entry.le32(0x0201_4b50); entry.le16(20); entry.le16(20); entry.le16(0x0800); entry.le16(0)
        entry.le16(time); entry.le16(date); entry.le32(crc)
        entry.le32(UInt32(data.count)); entry.le32(UInt32(data.count))
        entry.le16(UInt16(name.count)); entry.le16(0); entry.le16(0) // name, extra, comment lengths
        entry.le16(0); entry.le16(0); entry.le32(0) // disk, internal attrs, external attrs
        entry.le32(offset)
        central += entry + name
        count += 1
    }

    func data() -> Data {
        var end = Data()
        end.le32(0x0605_4b50); end.le16(0); end.le16(0)
        end.le16(count); end.le16(count)
        end.le32(UInt32(central.count)); end.le32(UInt32(body.count)); end.le16(0)
        return body + central + end
    }

    private func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour! << 11) | (c.minute! << 5) | (c.second! / 2))
        let day = UInt16(((max(c.year!, 1980) - 1980) << 9) | (c.month! << 5) | c.day!)
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
