import AppKit

/// Debug aid: `TEXTIFY_SNAPSHOT_DIR=/path TEXTIFY_SNAPSHOT_IMAGE=/img.png Textify`
/// renders the panel in each state to PNGs (own window only — needs no Screen Recording permission), then quits.
@MainActor
enum DebugSnapshots {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if env["TEXTIFY_TEST_CMDV"] != nil { testCommandV(); return }
        guard let dir = env["TEXTIFY_SNAPSHOT_DIR"] else { return }
        let vm = TextifyViewModel.shared
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            snap(dir, "1-idle")
            vm.panelFocusChanged(isKey: false)
            try? await Task.sleep(for: .milliseconds(300))
            snap(dir, "1b-idle-unfocused")
            vm.panelFocusChanged(isKey: true)
            if let img = env["TEXTIFY_SNAPSHOT_IMAGE"] {
                vm.process(url: URL(fileURLWithPath: img))
                try? await Task.sleep(for: .milliseconds(80))
                snap(dir, "2-processing")
                while vm.status == .processing { try? await Task.sleep(for: .milliseconds(100)) }
                // Auto-save (label + table detection) finishes after the clipboard copy; wait for it.
                if TextFileSaver.isEnabled {
                    for _ in 0..<80 where vm.savedURL == nil && vm.saveError == nil {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                try? await Task.sleep(for: .milliseconds(300))
                snap(dir, "3-result")
            }
            vm.clear(); vm.status = .noText
            try? await Task.sleep(for: .milliseconds(300)); snap(dir, "4-notext")
            vm.status = .idle; vm.showSettings = true
            try? await Task.sleep(for: .milliseconds(300)); snap(dir, "5-settings")
            if let scroll = NSApp.windows.first(where: { $0 is TextifyPanel })?.contentView?.firstScrollView {
                scroll.documentView?.scroll(NSPoint(x: 0, y: 420))
                try? await Task.sleep(for: .milliseconds(300)); snap(dir, "6-settings-middle")
                scroll.documentView?.scroll(NSPoint(x: 0, y: 10_000))
                try? await Task.sleep(for: .milliseconds(300)); snap(dir, "7-settings-bottom")
            }
            NSApp.terminate(nil)
        }
    }

    /// Posts a synthetic ⌘V to the panel and reports what the view model did.
    private static func testCommandV() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard let panel = NSApp.windows.first(where: { $0 is TextifyPanel }) else { print("no panel"); exit(1) }
            print("panel isKey:", panel.isKeyWindow, "app active:", NSApp.isActive)
            let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                      context: nil, characters: "v", charactersIgnoringModifiers: "v",
                                      isARepeat: false, keyCode: 9)!
            NSApp.postEvent(ev, atStart: false)
            try? await Task.sleep(for: .milliseconds(200))
            while TextifyViewModel.shared.status == .processing { try? await Task.sleep(for: .milliseconds(100)) }
            print("status after ⌘V:", TextifyViewModel.shared.status)
            exit(0)
        }
    }

    private static func snap(_ dir: String, _ name: String) {
        guard let view = NSApp.windows.first(where: { $0 is TextifyPanel })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}

private extension NSView {
    /// First NSScrollView in this view's subtree (used to scroll Settings for a second snapshot).
    var firstScrollView: NSScrollView? {
        if let s = self as? NSScrollView { return s }
        for sub in subviews { if let s = sub.firstScrollView { return s } }
        return nil
    }
}
