import AppKit

/// A future event (date + time) found in the text.
struct DetectedEvent: Equatable {
    var title: String
    let start: Date
    let end: Date
    let location: String?
    /// The line the event was found on — kept in the calendar entry's notes.
    let sourceLine: String

    var whenText: String {
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let time = DateFormatter()
        time.timeStyle = .short
        return "\(day.string(from: start)), \(time.string(from: start))–\(time.string(from: end))"
    }
}

/// Finds events with Apple's built-in date detector (understands English and Hebrew phrasing),
/// and names them with the on-device model when available.
enum EventDetector {
    private static let enabledKey = "detectEvents"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Requires an explicit time so plain dates (invoices, articles, receipts) don't become events.
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\d{1,2}[:.]\d{2}|\b\d{1,2}\s?(am|pm|a\.m\.|p\.m\.)|\bnoon\b|\bmidnight\b|בשעה"#,
        options: [.caseInsensitive])

    static func detect(in text: String, now: Date = Date()) async -> [DetectedEvent] {
        let candidates = candidates(in: text, now: now)
        var events: [DetectedEvent] = []
        for var event in candidates {
            event.title = await title(for: event, fullText: text)
            events.append(event)
        }
        return events
    }

    /// Date/time matches that are in the future and include a time. At most three.
    static func candidates(in text: String, now: Date = Date()) -> [DetectedEvent] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let location = address(in: text)
        var events: [DetectedEvent] = []
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            let ns = line as NSString
            for match in detector.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard let start = match.date, start > now.addingTimeInterval(-3600) else { continue }
                let matched = ns.substring(with: match.range)
                guard timePattern.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) != nil
                else { continue }
                guard !events.contains(where: { $0.start == start }) else { continue }
                let end = start.addingTimeInterval(match.duration > 0 ? match.duration : 3600)
                events.append(DetectedEvent(title: fallbackTitle(line: line, matched: matched),
                                            start: start, end: end, location: location, sourceLine: line))
                if events.count == 3 { return events }
            }
        }
        return events
    }

    private static func address(in text: String) -> String? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
              let m = d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r]).replacingOccurrences(of: "\n", with: ", ")
    }

    /// The model writes English titles; Hebrew lines keep their own words instead.
    private static func title(for event: DetectedEvent, fullText: String) async -> String {
        if HebrewOCRService.containsHebrew(event.sourceLine) { return event.title }
        let answer = await FileLabeler.askModel(instructions: """
            You name calendar events found in screenshots. Reply with a short event title of 2 to 6 words \
            in Title Case, without the date or time. Reply with the title only.
            Examples: "Team Sync", "Flight LY008 to New York", "Dentist Appointment", "Product Webinar".
            """, prompt: "Event line: \(event.sourceLine)\n\nSurrounding text:\n\(fullText.prefix(800))")
        return answer.flatMap(FileLabeler.sanitize) ?? event.title
    }

    /// The line with the date/time phrase removed, e.g. "Team sync on … in Room 4B" → "Team sync in Room 4B".
    static func fallbackTitle(line: String, matched: String) -> String {
        var s = line.replacingOccurrences(of: matched, with: " ")
        for filler in [" on ", " at ", " for ", " ב-", " ב "] {
            s = s.replacingOccurrences(of: filler + " ", with: " ")
        }
        s = s.split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:,.·|").union(.whitespaces))
        for suffix in [" on", " at", " ב"] where s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        return s.isEmpty ? "Event" : String(s.prefix(60))
    }

    // MARK: - Calendar

    /// Writes the event as an .ics file and opens it, so Calendar offers to add it.
    /// No Calendar permission is needed; the file lives in a temporary folder.
    static func addToCalendar(_ event: DetectedEvent) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TEXTIFY Events", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = FileLabeler.sanitize(event.title) ?? "Event"
        let url = dir.appendingPathComponent("\(name).ics")
        try ics(for: event).write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    static func ics(for event: DetectedEvent, now: Date = Date()) -> String {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//TEXTIFY//EN", "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@textify",
            "DTSTAMP:\(utc.string(from: now))",
            "DTSTART:\(utc.string(from: event.start))",
            "DTEND:\(utc.string(from: event.end))",
            "SUMMARY:\(escapeICS(event.title))",
        ]
        if let location = event.location { lines.append("LOCATION:\(escapeICS(location))") }
        lines.append("DESCRIPTION:\(escapeICS("From a screenshot: " + event.sourceLine))")
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func escapeICS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// RFC 5545 line folding: lines longer than 75 bytes continue on the next line after a space.
    private static func fold(_ line: String) -> String {
        var out = "", current = 0
        for ch in line {
            let size = String(ch).utf8.count
            if current + size > 75 { out += "\r\n "; current = 1 }
            out.append(ch); current += size
        }
        return out
    }
}
