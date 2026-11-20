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

        // Same image again: don't re-run OCR, just make sure the text is back on the clipboard.
        if !force, fp == lastFingerprint, hasResult {
            copyToClipboard()
            return
        }

        task?.cancel()
        lastFingerprint = fp
        lastImage = image
        status = .processing
        partiallyReadable = false
        savedURL = nil
        saveError = nil

        task = Task {
            do {
                let result = try await OCRService.recognizeText(in: image)
                guard !Task.isCancelled else { return }
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // Leave the clipboard untouched.
                    text = ""
                    status = .noText
                    return
                }
                text = trimmed
                partiallyReadable = result.hasLowConfidence
                copyToClipboard()
                await saveIfEnabled()
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    // MARK: - Actions

    func copyToClipboard() {
        guard hasResult else { return }
        do {
            try clipboard.writeText(text)
            status = .copied
        } catch {
            status = .copyFailed(error.localizedDescription)
        }
    }

    /// Writes the result to disk when the user opted in. Only called for fresh OCR results,
    /// so pasting the same image twice doesn't create duplicate files.
    /// The clipboard is already updated before this runs; labeling only delays the file.
    private func saveIfEnabled() async {
        guard TextFileSaver.isEnabled, hasResult else { return }
        let captured = text
        let label = await FileLabeler.label(for: captured)
        guard !Task.isCancelled, text == captured else { return } // a newer result replaced this one
        do {
            savedURL = try TextFileSaver.save(captured, label: label)
            saveError = nil
        } catch {
            savedURL = nil
            saveError = "Copied, but couldn't save file: \(error.localizedDescription)"
        }
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
