import AppKit
import SwiftUI

/// Single source of truth for the panel UI.
@MainActor
final class TextifyViewModel: ObservableObject {
    static let shared = TextifyViewModel()

    enum Status: Equatable {
        case idle
        case processing
        case copied            // text extracted and on the clipboard
        case copyFailed(String) // text extracted but clipboard write failed
        case noText
        case error(String)
    }

    @Published var status: Status = .idle
    @Published var text: String = ""
    @Published var partiallyReadable = false
    @Published var showSettings = false
    /// File the latest result was auto-saved to (when "Save to file" is on).
    @Published var savedURL: URL?
    /// Why auto-save failed, if it did. The clipboard copy still stands.
    @Published var saveError: String?
    /// Tables detected in the current image (macOS 26+). When non-empty, the clipboard also carries them as cells.
    @Published private(set) var tables: [ExtractedTable] = []

    // Smart detection results for the current image.
    @Published private(set) var codes: [DetectedCode] = []
    @Published private(set) var events: [DetectedEvent] = []
    @Published private(set) var receipt: DetectedReceipt?
    /// Set once the receipt is in Expenses.csv (added now or already there).
    @Published private(set) var receiptLedger: URL?
    /// The code whose content was auto-copied instead of the text, if any.
    @Published private(set) var copiedCode: DetectedCode?
    /// Raw OCR text (the visible text may instead describe a QR code when the image had no text).
    private var ocrText = ""

    /// Full status-line message after a successful copy, including what was saved.
    var successMessage: String {
        guard let saved = savedURL else { return copiedMessage }
        if copiedCode != nil { return String(copiedMessage.dropLast()) + " · saved" }
        return saved.pathExtension == "xlsx" ? "Copied & saved table to Excel!" : "Copied & saved!"
    }

    /// Status-line message for a successful copy.
    var copiedMessage: String {
        guard let code = copiedCode else { return "Copied to clipboard!" }
        switch code.kind {
        case .link: return "Copied QR link!"
        case .wifi(_, let password): return password == nil ? "Copied Wi-Fi network name!" : "Copied Wi-Fi password!"
        case .text: return "Copied QR code content!"
        }
    }
    /// Whether the panel has keyboard focus (⌘V only reaches TEXTIFY when it does).
    @Published var panelIsKey = false
    private var becameKeyAt = Date.distantPast

    func panelFocusChanged(isKey: Bool) {
        panelIsKey = isKey
        if isKey { becameKeyAt = Date() }
    }

    /// True right after a click brought the panel into focus — used to swallow that "focus click".
    var panelJustBecameKey: Bool { Date().timeIntervalSince(becameKeyAt) < 0.5 }

    private let clipboard = ClipboardManager.shared
    private var lastFingerprint: String?
    private var lastImage: CGImage?
    private var task: Task<Void, Never>?

    var hasResult: Bool { !text.isEmpty }

    // MARK: - Inputs

    /// ⌘V / global hotkey / menu: process the image currently on the clipboard.
    func processClipboard() {
        do {
            let image = try clipboard.readImage()
            process(image)
        } catch ClipboardError.noImage where clipboard.clipboardIsOurOwnText && hasResult {
            // The clipboard holds the text we just extracted — nothing new to do.
            status = .copied
        } catch {
            fail(error)
        }
    }

    func process(url: URL) {
        do { process(try ImageLoader.load(url: url)) } catch { fail(error) }
    }

    func process(data: Data) {
        do { process(try ImageLoader.load(data: data)) } catch { fail(error) }
    }

    /// Re-run OCR on the last image even if it was already processed.
    func rescan() {
        guard let img = lastImage else { return }
        process(img, force: true)
    }

    // MARK: - Core pipeline

    func process(_ image: CGImage, force: Bool = false) {
        let fp = ImageLoader.fingerprint(image)

        // Same image again: don't re-run OCR, just make sure the result is back on the clipboard.
        if !force, fp == lastFingerprint, hasResult {
            autoCopy()
            return
        }

        task?.cancel()
        lastFingerprint = fp
        lastImage = image
        status = .processing
        partiallyReadable = false
        savedURL = nil
        saveError = nil
        resetDetections()

        task = Task {
            do {
                // QR/barcode detection runs alongside OCR: it decides what goes on the clipboard.
                async let foundCodes = BarcodeDetector.detect(in: image)
                let result = try await OCRService.recognizeText(in: image)
                let found = await foundCodes
                guard !Task.isCancelled else { return }
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && found.isEmpty {
                    // Leave the clipboard untouched.
                    text = ""
                    status = .noText
                    return
                }
                ocrText = trimmed
                codes = found
                text = trimmed.isEmpty ? found.map(\.displayText).joined(separator: "\n\n") : trimmed
                partiallyReadable = result.hasLowConfidence
                autoCopy()
                await enrichAndSave(image)
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    // MARK: - Actions

    /// Copy button: always copies the visible text (plus any tables as cells).
    func copyToClipboard() {
        guard hasResult else { return }
        write(text, tables: tables, code: nil)
    }

    /// Automatic copy after extraction: a prominent QR code's content, otherwise the text.
    private func autoCopy() {
        guard hasResult else { return }
        if let code = codes.first, BarcodeDetector.shouldCopyCode(code, ocrText: ocrText) {
            write(code.copyValue, tables: [], code: code)
        } else {
            write(text, tables: tables, code: nil)
        }
    }

    private func write(_ value: String, tables: [ExtractedTable], code: DetectedCode?) {
        do {
            try clipboard.writeText(value, tables: tables)
            copiedCode = code
            status = .copied
        } catch {
            status = .copyFailed(error.localizedDescription)
        }
    }

    func copyCode(_ code: DetectedCode) { write(code.copyValue, tables: [], code: code) }

    func openCode(_ code: DetectedCode) { BarcodeDetector.open(code) }

    func addToCalendar(_ event: DetectedEvent) {
        do { try EventDetector.addToCalendar(event) } catch {
            saveError = "Couldn't create the calendar event: \(error.localizedDescription)"
        }
    }

    func addReceiptToLedger() {
        guard let receipt else { return }
        do {
            switch try ExpenseLedger.log(receipt, savedFile: savedURL) {
            case .added(let url), .duplicate(let url): receiptLedger = url
            }
        } catch {
            saveError = "Couldn't add to \(ExpenseLedger.fileName): \(error.localizedDescription)"
        }
    }

    func revealLedger() {
        if let url = receiptLedger { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func resetDetections() {
        tables = []
        codes = []
        events = []
        receipt = nil
        receiptLedger = nil
        copiedCode = nil
        ocrText = ""
    }

    /// Runs after the plain text is already on the clipboard (so pasting is never delayed):
    /// 1. detects tables and, if found, upgrades the clipboard with spreadsheet-ready cells —
    ///    only if the clipboard still holds our text (never clobbers something the user copied since);
    /// 2. saves to disk when the user opted in. Only called for fresh OCR results,
    ///    so pasting the same image twice doesn't create duplicate files.
    private func enrichAndSave(_ image: CGImage) async {
        guard hasResult else { return }
        let captured = text
        let wantSave = TextFileSaver.isEnabled

        // Receipts are parsed instantly; events, labels and tables run concurrently.
        let parsedReceipt = ReceiptParser.parse(ocrText)
        receipt = parsedReceipt
        let source = ocrText
        let wantEvents = EventDetector.isEnabled && parsedReceipt == nil // receipt timestamps aren't events
        async let labelTask: String? = wantSave ? FileLabeler.label(for: captured) : nil
        async let eventsTask: [DetectedEvent] = wantEvents ? EventDetector.detect(in: source) : []
        let found: [ExtractedTable] = TableExtractor.isSupported
            ? await TableExtractor.tables(in: image, containsHebrew: HebrewOCRService.containsHebrew(captured))
            : []
        guard !Task.isCancelled, text == captured else { return } // a newer result replaced this one

        if !found.isEmpty {
            tables = found
            // Upgrade to spreadsheet cells only if our text (not a QR value) is still on the clipboard.
            if copiedCode == nil, clipboard.clipboardIsOurOwnText { try? clipboard.writeText(captured, tables: found) }
        }
        events = await eventsTask
        guard !Task.isCancelled, text == captured else { return }

        guard wantSave else { return }
        let label = await labelTask
        guard !Task.isCancelled, text == captured else { return }
        do {
            savedURL = try TextFileSaver.save(captured, label: label,
                                              tables: TableExtractor.isEnabled ? found : [])
            saveError = nil
        } catch {
            savedURL = nil
            saveError = "Copied, but couldn't save file: \(error.localizedDescription)"
        }
        if receipt != nil, ExpenseLedger.isEnabled { addReceiptToLedger() }
    }

    func revealSavedFile() {
        guard let url = savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clear() {
        task?.cancel()
        text = ""
        savedURL = nil
        saveError = nil
        resetDetections()
        status = .idle
        partiallyReadable = false
        lastImage = nil
        lastFingerprint = nil
    }

    /// Escape: close settings, else clear the result, else hide the panel.
    func handleEscape() {
        if showSettings {
            showSettings = false
        } else if status != .idle || hasResult {
            clear()
        } else {
            FloatingPanelManager.shared.hide()
        }
    }

    func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageLoader.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a screenshot or image"
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            process(url: url)
        }
        FloatingPanelManager.shared.show()
    }

    private func fail(_ error: Error) {
        status = .error(error.localizedDescription)
    }
}
