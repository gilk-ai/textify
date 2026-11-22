import Foundation

/// Hebrew text writes numeric dates day-first ("2.12.2026" is 2 December), whatever region the Mac is set to.
/// Apple's date detector follows the Mac's region, so on a US-region Mac it reads such dates month-first
/// (12 February). This re-reads numeric dates in Hebrew text as day-first, keeping the detected time of day.
enum DateOrder {
    private static let numeric = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)"#)

    static func dayFirst(_ date: Date, matched: String, context: String) -> Date {
        guard HebrewOCRService.containsHebrew(context) else { return date }
        let ns = matched as NSString
        guard let m = numeric.firstMatch(in: matched, range: NSRange(location: 0, length: ns.length)),
              let day = Int(ns.substring(with: m.range(at: 1))),
              let month = Int(ns.substring(with: m.range(at: 2))),
              var year = Int(ns.substring(with: m.range(at: 3))),
              (1...31).contains(day), (1...12).contains(month)
        else { return date }
        if year < 100 { year += 2000 }
        let calendar = Calendar(identifier: .gregorian)
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        let parts = DateComponents(year: year, month: month, day: day,
                                   hour: time.hour, minute: time.minute, second: time.second)
        return calendar.date(from: parts) ?? date
    }

    /// The first numeric date in a Hebrew line, read day-first, with its range. Used when Apple's detector
    /// misses it (it does when the Mac's language isn't Hebrew).
    static func hebrewDate(in line: String) -> (date: Date, range: NSRange)? {
        guard HebrewOCRService.containsHebrew(line) else { return nil }
        let ns = line as NSString
        guard let m = numeric.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let midnight = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let date = dayFirst(midnight, matched: ns.substring(with: m.range), context: line)
        return date == midnight ? nil : (date, m.range)
    }
}
