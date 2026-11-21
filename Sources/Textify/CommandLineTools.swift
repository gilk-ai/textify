import Foundation

/// Headless entry points used for testing the OCR + clipboard pipeline without the UI.
///   Textify --ocr <image>      print recognized text
///   Textify --ocr-clipboard    OCR the clipboard image and copy the text back (same path as ⌘V)
///   Textify --label <image>    print the auto-save label for an image's text
///   Textify --table <image> [--xlsx out.xlsx]   print detected tables, optionally export them
///       [--save-to <dir> [--append]]  also save the text, overriding the Settings choice
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
                if text.isEmpty { fputs("No text found. Clipboard unchanged.\n", stderr); exit(2) }
                try ClipboardManager.shared.writeText(text)
                print("Copied \(text.count) characters to clipboard.")
                // Same opt-in auto-save as the app. `--save-to <dir>` forces it on for testing.
                if let i = args.firstIndex(of: "--save-to"), i + 1 < args.count {
                    let (label, tables) = blocking { await TextFileSaver.prepare(text: text, image: image) }
                    let url = try TextFileSaver.save(text, label: label, tables: tables, to: URL(fileURLWithPath: args[i + 1], isDirectory: true),
                                                     mode: args.contains("--append") ? .append : .newFile)
                    print("Saved to \(url.path)")
                } else if TextFileSaver.isEnabled {
                    let (label, tables) = blocking { await TextFileSaver.prepare(text: text, image: image) }
                    print("Saved to \(try TextFileSaver.save(text, label: label, tables: tables).path)")
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
