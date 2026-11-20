import Foundation

/// Headless entry points used for testing the OCR + clipboard pipeline without the UI.
///   Textify --ocr <image>      print recognized text
///   Textify --ocr-clipboard    OCR the clipboard image and copy the text back (same path as ⌘V)
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
        if args.contains("--ocr-clipboard") {
            do {
                let image = try ClipboardManager.shared.readImage()
                let result = try OCRService.recognizeSync(image)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { fputs("No text found. Clipboard unchanged.\n", stderr); exit(2) }
                try ClipboardManager.shared.writeText(text)
                print("Copied \(text.count) characters to clipboard.")
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        return false
    }
}
