import AppKit
import SwiftUI

/// Borderless floating panel that can become key (needed for ⌘V / Esc / text selection).
final class TextifyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the single TEXTIFY panel and its keyboard handling.
@MainActor
final class FloatingPanelManager: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelManager()

    static let size = NSSize(width: 340, height: 400)
    private var panel: TextifyPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    private func makePanel() -> TextifyPanel {
        let panel = TextifyPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let host = NSHostingView(rootView: ContentView().environmentObject(TextifyViewModel.shared))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host

        // Restore last position, or place near the top-right of the screen.
        if !panel.setFrameUsingName("TextifyPanel"), let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - Self.size.width - 24,
                                         y: vf.maxY - Self.size.height - 24))
        }
        panel.setFrameAutosaveName("TextifyPanel")

        installKeyMonitor()
        self.panel = panel
        return panel
    }

    /// Intercepts ⌘V and Esc while the panel is key. Everything else (⌘C, ⌘A…) flows normally.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let vm = TextifyViewModel.shared

            if event.keyCode == 53 { // Escape
                vm.handleEscape()
                return nil
            }
            if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
                vm.processClipboard()
                return nil
            }
            if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                self.hide()
                return nil
            }
            if mods == .command, event.charactersIgnoringModifiers == "," {
                vm.showSettings.toggle()
                return nil
            }
            return event
        }
    }
}
