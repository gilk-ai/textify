import Foundation

/// The key facts of a receipt or invoice.
struct DetectedReceipt: Equatable {
    let vendor: String
    let date: Date?
    let total: Decimal
    let vat: Decimal?
    let currency: String?   // ISO code: ILS, USD, EUR, GBP

    var summary: String {
        var parts = [Self.format(total, currency)]
        if let vat { parts.append("VAT \(Self.format(vat, currency))") }
        if let date {
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
            parts.append(f.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    static func format(_ amount: Decimal, _ currency: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let n = f.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        switch currency {
        case "ILS": return "₪\(n)"
        case "USD": return "$\(n)"
        case "EUR": return "€\(n)"
        case "GBP": return "£\(n)"
        default: return n
        }
    }
}

/// Rule-based receipt reader for English and Hebrew receipts. Deterministic and fully local.
enum ReceiptParser {
    /// Lines that announce the amount actually paid, strongest first.
    private static let strongTotals = ["total due", "amount due", "balance due", "grand total", "total to pay",
                                       "amount paid", "סה\"כ לתשלום", "לתשלום", "סך הכל לתשלום"]
    private static let totals = ["total", "סה\"כ", "סהכ", "סך הכל", "סך הכול"]
    private static let notTotals = ["subtotal", "sub total", "sub-total", "before vat", "before tax", "excl",
                                    "לפני מע\"מ", "לפני מעמ", "ללא מע\"מ", "total items", "total qty"]
    private static let vatWords = ["vat", "tax", "gst", "מע\"מ", "מעמ"]
    private static let receiptWords = ["receipt", "invoice", "order", "cashier", "thank you", "payment", "paid",
                                       "קבלה", "חשבונית", "תודה", "קופה", "אשראי", "עוסק"]

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(?:[₪$€£]\s?)?-?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}(?!\d)(?!\s?%)|[₪$€£]\s?\d+(?![\d.,%])"#)

    static func parse(_ text: String, now: Date = Date()) -> DetectedReceipt? {
        let lines = text.components(separatedBy: "\n").map(normalize).filter { !$0.isEmpty }
        let lower = lines.map { $0.lowercased() }

        guard let total = findTotal(lines: lines, lower: lower) else { return nil }
        let allAmounts = lines.flatMap(amounts)
        guard allAmounts.count >= 2 else { return nil }

        let currency = detectCurrency(text)
        let vat = findVAT(lines: lines, lower: lower, total: total)
        let date = findDate(text, now: now)
        // A "total" alone (e.g. a sales table) isn't enough — require something receipt-like too.
        let receiptish = vat != nil || currency != nil || date != nil
            || receiptWords.contains { w in lower.contains { $0.contains(w) } }
        guard receiptish else { return nil }

        return DetectedReceipt(vendor: findVendor(lines: lines, lower: lower), date: date,
                               total: total, vat: vat, currency: currency)
    }

    // MARK: - Fields

    private static func findTotal(lines: [String], lower: [String]) -> Decimal? {
        for tier in [strongTotals, totals] {
            var found: [Decimal] = []
            for (i, line) in lower.enumerated()
            where tier.contains(where: line.contains) && !notTotals.contains(where: line.contains) {
                // The amount is usually on the same line; OCR sometimes puts it on the next one.
                let here = amounts(in: lines[i])
                let values = here.isEmpty && i + 1 < lines.count ? amounts(in: lines[i + 1]) : here
                if let v = values.max() { found.append(v) }
            }
            if let best = found.max(), best > 0 { return best }
        }
        return nil
    }

    private static func findVAT(lines: [String], lower: [String], total: Decimal) -> Decimal? {
        for (i, line) in lower.enumerated() where vatWords.contains(where: line.contains) {
            // Skip "total before VAT" style lines; take a VAT amount smaller than the total.
            if notTotals.contains(where: line.contains) || strongTotals.contains(where: line.contains) { continue }
            if let v = amounts(in: lines[i]).filter({ $0 < total }).min() { return v }
        }
        return nil
    }

    private static func findDate(_ text: String, now: Date) -> Date? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let latest = now.addingTimeInterval(86_400)
        let ns = text as NSString
        return d.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in m.date.map { DateOrder.dayFirst($0, matched: ns.substring(with: m.range), context: text) } }
            .first { $0 <= latest }
    }

    /// The vendor is normally the first real line at the top of the receipt.
    private static func findVendor(lines: [String], lower: [String]) -> String {
        for (i, line) in lines.prefix(6).enumerated() {
            let l = lower[i]
            let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letters >= 3, amounts(in: line).isEmpty,
                  !(totals + strongTotals + vatWords).contains(where: l.contains),
                  !["receipt", "invoice", "קבלה", "חשבונית", "date", "תאריך"].contains(where: { l.hasPrefix($0) })
            else { continue }
            return String(line.prefix(50)).trimmingCharacters(in: .whitespaces)
        }
        return "Unknown vendor"
    }

    private static func detectCurrency(_ text: String) -> String? {
        let t = text.uppercased()
        if t.contains("₪") || t.contains("ש\"ח") || t.contains("ש״ח") || t.contains("NIS") || t.contains("ILS") { return "ILS" }
        if t.contains("€") || t.contains("EUR") { return "EUR" }
        if t.contains("£") || t.contains("GBP") { return "GBP" }
        if t.contains("$") || t.contains("USD") { return "USD" }
        return nil
    }

    // MARK: - Helpers

    static func amounts(in line: String) -> [Decimal] {
        let ns = line as NSString
        return amountRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
            let raw = ns.substring(with: $0.range)
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "₪$€£ "))
            return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// Unifies the many ways OCR renders Hebrew gershayim (״ " ” '') so keyword matching works.
    private static func normalize(_ line: String) -> String {
        line.replacingOccurrences(of: "״", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "''", with: "\"")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Appends receipts to `Expenses.csv` in the save folder. CSV (not .xlsx) so rows can be appended
/// safely and any edits made in Excel/Numbers are never overwritten. Opens in Excel with a double-click.
enum ExpenseLedger {
    static let fileName = "Expenses.csv"
    private static let enabledKey = "logReceipts"
    private static let header = "Date,Vendor,Total,VAT,Currency,Saved file,Captured at"

    /// Setting: log receipts automatically when "Save to file" is on.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    enum Outcome: Equatable { case added(URL), duplicate(URL) }

    @discardableResult
    static func log(_ receipt: DetectedReceipt, savedFile: URL? = nil,
                    folder: URL = TextFileSaver.folder, now: Date = Date()) throws -> Outcome {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm"

        let fields = [
            receipt.date.map(iso.string(from:)) ?? "",
            receipt.vendor,
            plain(receipt.total),
            receipt.vat.map(plain) ?? "",
            receipt.currency ?? "",
            savedFile?.lastPathComponent ?? "",
            stamp.string(from: now),
        ]
        let row = fields.map(csvEscape).joined(separator: ",")

        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            // Same date + vendor + total already logged (e.g. the receipt was re-scanned) → skip.
            let key = fields.prefix(3).map(csvEscape).joined(separator: ",") + ","
            if existing.components(separatedBy: "\n").contains(where: { $0.hasPrefix(key) }) { return .duplicate(url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let prefix = existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n"
            try handle.write(contentsOf: Data((prefix + row + "\n").utf8))
        } else {
            // UTF-8 byte-order mark so Excel shows Hebrew vendor names correctly.
            try ("\u{FEFF}" + header + "\n" + row + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        return .added(url)
    }

    /// "32.00" — two decimals, no grouping, so spreadsheets read it as a number.
    private static func plain(_ amount: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: amount).doubleValue)
    }

    private static func csvEscape(_ s: String) -> String {
        // Also neutralize spreadsheet formula injection (cells starting with = + - @).
        var v = s
        if let first = v.first, "=+@".contains(first) || (first == "-" && Decimal(string: v) == nil) { v = "'" + v }
        return v.contains(where: { ",\"\n".contains($0) }) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }
}
