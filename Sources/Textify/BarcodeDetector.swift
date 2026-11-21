import AppKit
import Vision

/// A QR code or barcode found in the image.
struct DetectedCode: Equatable {
    enum Kind: Equatable {
        case link(URL)
        case wifi(ssid: String, password: String?)
        case text
    }

    let payload: String
    let kind: Kind
    /// Fraction of the image the code covers (0…1) — big codes are what the screenshot is "about".
    let areaFraction: Double

    /// What goes on the clipboard: the link, the Wi-Fi password, or the raw text.
    var copyValue: String {
        if case .wifi(let ssid, let password) = kind { return password ?? ssid }
        return payload
    }

    var title: String {
        switch kind {
        case .link(let url): return url.host ?? url.absoluteString
        case .wifi(let ssid, _): return "Wi-Fi: \(ssid)"
        case .text: return "QR code"
        }
    }

    var subtitle: String {
        switch kind {
        case .link(let url): return url.absoluteString
        case .wifi(_, let password): return password.map { "Password: \($0)" } ?? "Open network"
        case .text: return payload
        }
    }

    /// Text shown in the result area when the image has no other text.
    var displayText: String {
        if case .wifi(let ssid, let password) = kind {
            return "Wi-Fi network: \(ssid)" + (password.map { "\nPassword: \($0)" } ?? "")
        }
        return payload
    }
}

/// Finds QR codes and barcodes with Vision (on-device).
enum BarcodeDetector {
    private static let copyKey = "qrCopyContent"

    /// Setting: when a prominent code is found, put its content (not the OCR text) on the clipboard.
    static var copyCodeContent: Bool {
        get { UserDefaults.standard.object(forKey: copyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyKey) }
    }

    /// Only these schemes may be opened from a QR code; anything else is just copied.
    static let openableSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    static func detect(in image: CGImage) async -> [DetectedCode] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: detectSync(image))
            }
        }
    }

    static func detectSync(_ image: CGImage) -> [DetectedCode] {
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var seen = Set<String>()
        return (request.results ?? [])
            .compactMap { obs -> DetectedCode? in
                guard let payload = obs.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !payload.isEmpty, seen.insert(payload).inserted else { return nil }
                let area = Double(obs.boundingBox.width * obs.boundingBox.height)
                return DetectedCode(payload: payload, kind: kind(of: payload), areaFraction: area)
            }
            .sorted { $0.areaFraction > $1.areaFraction }
    }

    /// Should the code's content replace the OCR text on the clipboard?
    /// Yes when the code is what the screenshot is about: it's large, or there's little other text.
    static func shouldCopyCode(_ code: DetectedCode, ocrText: String) -> Bool {
        guard copyCodeContent else { return ocrText.isEmpty }
        return ocrText.isEmpty || code.areaFraction >= 0.03 || ocrText.count < 200
    }

    static func kind(of payload: String) -> DetectedCode.Kind {
        if payload.uppercased().hasPrefix("WIFI:"), let wifi = parseWiFi(payload) { return wifi }
        if let url = URL(string: payload), let scheme = url.scheme?.lowercased(),
           openableSchemes.contains(scheme), scheme == "mailto" || scheme == "tel" || url.host != nil {
            return .link(url)
        }
        return .text
    }

    /// Parses `WIFI:T:WPA;S:name;P:secret;;` (fields may appear in any order; \ escapes ; , : \).
    static func parseWiFi(_ payload: String) -> DetectedCode.Kind? {
        var fields: [String: String] = [:]
        var key = "", value = "", inValue = false, escaped = false
        for ch in payload.dropFirst(5) {
            if escaped { value.append(ch); escaped = false; continue }
            switch ch {
            case "\\": escaped = true
            case ":" where !inValue: inValue = true
            case ";":
                if !key.isEmpty { fields[key.uppercased()] = value }
                key = ""; value = ""; inValue = false
            default:
                if inValue { value.append(ch) } else { key.append(ch) }
            }
        }
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let password = fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        return .wifi(ssid: ssid, password: password)
    }

    /// Opens a link from a QR code — only for safe, expected schemes.
    static func open(_ code: DetectedCode) {
        guard case .link(let url) = code.kind,
              let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}
