import AppKit

/// Debug aid: `TEXTIFY_SNAPSHOT_DIR=/path TEXTIFY_SNAPSHOT_IMAGE=/img.png Textify`
/// renders the panel in each state to PNGs (own window only — needs no Screen Recording permission), then quits.
@MainActor
enum DebugSnapshots {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TEXTIFY_SNAPSHOT_DIR"] else { return }
        let vm = TextifyViewModel.shared
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            snap(dir, "1-idle")
            if let img = env["TEXTIFY_SNAPSHOT_IMAGE"] {
                vm.process(url: URL(fileURLWithPath: img))
                try? await Task.sleep(for: .milliseconds(80))
                snap(dir, "2-processing")
                while vm.status == .processing { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .milliseconds(300))
                snap(dir, "3-result")
            }
            vm.clear(); vm.status = .noText
            try? await Task.sleep(for: .milliseconds(300)); snap(dir, "4-notext")
            vm.status = .idle; vm.showSettings = true
            try? await Task.sleep(for: .milliseconds(300)); snap(dir, "5-settings")
            NSApp.terminate(nil)
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
