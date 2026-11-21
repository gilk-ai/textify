import Foundation
import ServiceManagement

/// Headless entry points used for testing the OCR + clipboard pipeline without the UI.
///   Textify --ocr <image>      print recognized text
///   Textify --ocr-clipboard    OCR the clipboard image and copy the text back (same path as ⌘V)
///   Textify --label <image>    print the auto-save label for an image's text
///   Textify --table <image> [--xlsx out.xlsx]   print detected tables, optionally export them
///       [--save-to <dir> [--append]] | [--no-save]   override the Settings save choice
///   Textify --detect <image> [--ics out.ics] [--log]   print QR codes, events and receipt found in an image
///   Textify --login-item on|off|status   manage "Launch at login" for this app bundle  also save the text, overriding the Settings choice
enum CommandLineTools {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ocr"), i + 1 < args.count {
            do {
                let image = try ImageLoader.load(url: URL(fileURLWithPath: args[i + 1]))
                let result = try OCRService.recognizeSync(image)
                if result.text.isEmpty { fputs("No text found.\n", stderr); exit(2) }
                print(result.text)
                if result.hasLowConfidence { fputs("(partially readable)\n", stderr) }
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if let i = args.firstIndex(of: "--label"), i + 1 < args.count {
            do {
                let image = try ImageLoader.load(url: URL(fileURLWithPath: args[i + 1]))
                let text = try OCRService.recognizeSync(image).text
                if text.isEmpty { fputs("No text found.\n", stderr); exit(2) }
                let start = Date()
                let label = blocking { await FileLabeler.label(for: text) }
                print(label + String(format: "    (%.2fs, heuristic: %@)", Date().timeIntervalSince(start),
                                     FileLabeler.heuristicLabel(for: text)))
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if let i = args.firstIndex(of: "--login-item"), i + 1 < args.count {
            let service = SMAppService.mainApp
            do {
                switch args[i + 1] {
                case "on": try service.register()
                case "off": try service.unregister()
                default: break
                }
                print("Launch at login: \(service.status == .enabled ? "on" : "off") (\(Bundle.main.bundlePath))")
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if let i = args.firstIndex(of: "--detect"), i + 1 < args.count {
            do {
                let image = try ImageLoader.load(url: URL(fileURLWithPath: args[i + 1]))
                let text = try OCRService.recognizeSync(image).text
                let codes = BarcodeDetector.detectSync(image)
                for c in codes {
                    print("QR: \(c.title) | copy: \(c.copyValue) | area \(String(format: "%.3f", c.areaFraction)) | copies code: \(BarcodeDetector.shouldCopyCode(c, ocrText: text))")
                }
                let events = blocking { await EventDetector.detect(in: text) }
                for e in events {
                    print("Event: \(e.title) | \(e.whenText)\(e.location.map { " | " + $0 } ?? "")")
                }
                if let j = args.firstIndex(of: "--ics"), j + 1 < args.count, let first = events.first {
                    try EventDetector.ics(for: first).write(toFile: args[j + 1], atomically: true, encoding: .utf8)
                    print("Wrote \(args[j + 1])")
                }
                if let r = ReceiptParser.parse(text) {
                    print("Receipt: \(r.vendor) | \(r.summary)")
                    if args.contains("--log") {
                        // Respects TEXTIFY_SAVE_DIR, so tests can log into a scratch folder.
                        switch try ExpenseLedger.log(r) {
                        case .added(let url): print("Logged to \(url.path)")
                        case .duplicate(let url): print("Already in \(url.path)")
                        }
                    }
                }
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if let i = args.firstIndex(of: "--table"), i + 1 < args.count {
            do {
                let image = try ImageLoader.load(url: URL(fileURLWithPath: args[i + 1]))
                let text = try OCRService.recognizeSync(image).text
                let tables = blocking {
                    await TableExtractor.tables(in: image, containsHebrew: HebrewOCRService.containsHebrew(text))
                }
                if tables.isEmpty { print("No clearly structured table found."); exit(2) }
                for (n, t) in tables.enumerated() {
                    print("Table \(n + 1): \(t.rowCount) rows × \(t.columnCount) columns\(t.isRightToLeft ? " (RTL)" : "")")
                    for r in 0..<t.rowCount {
                        let row = t.cells.filter { $0.row == r }.sorted { $0.column < $1.column }
                        print("  " + row.map { $0.text.replacingOccurrences(of: "\n", with: "⏎") }.joined(separator: " | "))
                    }
                }
                if let j = args.firstIndex(of: "--xlsx"), j + 1 < args.count {
                    try XLSXWriter.write(tables: tables, fullText: text, to: URL(fileURLWithPath: args[j + 1]))
                    print("Wrote \(args[j + 1])")
                }
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if args.contains("--ocr-clipboard") {
            do {
                let image = try ClipboardManager.shared.readImage()
                let result = try OCRService.recognizeSync(image)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let codes = BarcodeDetector.detectSync(image)
                if text.isEmpty && codes.isEmpty { fputs("No text found. Clipboard unchanged.\n", stderr); exit(2) }
                // Same rule as the app: a prominent QR code's content wins over the text.
                if let code = codes.first, BarcodeDetector.shouldCopyCode(code, ocrText: text) {
                    try ClipboardManager.shared.writeText(code.copyValue)
                    print("Copied QR content to clipboard.")
                    exit(0)
                }
                try ClipboardManager.shared.writeText(text)
                print("Copied \(text.count) characters to clipboard.")
                // Same enrichment as the app: tables also go on the clipboard as cells.
                let tables = TableExtractor.isSupported
                    ? blocking { await TableExtractor.tables(in: image, containsHebrew: HebrewOCRService.containsHebrew(text)) }
                    : []
                if !tables.isEmpty {
                    try ClipboardManager.shared.writeText(text, tables: tables)
                    print("Clipboard also holds \(tables.count) table(s) as HTML + tab-separated cells.")
                }
                // Same opt-in auto-save as the app. `--save-to <dir>` forces it on for testing.
                if let i = args.firstIndex(of: "--save-to"), i + 1 < args.count {
                    let label = blocking { await FileLabeler.label(for: text) }
                    let url = try TextFileSaver.save(text, label: label, tables: TableExtractor.isEnabled ? tables : [], to: URL(fileURLWithPath: args[i + 1], isDirectory: true),
                                                     mode: args.contains("--append") ? .append : .newFile)
                    print("Saved to \(url.path)")
                } else if TextFileSaver.isEnabled, !args.contains("--no-save") {
                    let label = blocking { await FileLabeler.label(for: text) }
                    print("Saved to \(try TextFileSaver.save(text, label: label, tables: TableExtractor.isEnabled ? tables : []).path)")
                }
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        return false
    }

    /// Bridges async work into these synchronous CLI paths.
    private static func blocking<T>(_ work: @escaping () async -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        var result: T?
        Task.detached {
            result = await work()
            done.signal()
        }
        done.wait()
        return result!
    }
}
