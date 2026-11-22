import AppKit
import SwiftUI

/// Borderless floating panel that can become key (needed for ⌘V / Esc / text selection).
final class TextifyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the single TEXTIFY panel, its keyboard handling, and the switch between the full panel
/// and the mini player (a slim bar that docks in the bottom corners, beside the Dock).
@MainActor
final class FloatingPanelManager: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = FloatingPanelManager()

    static let size = NSSize(width: 340, height: 400)
    static let miniSize = NSSize(width: 300, height: 46)

    enum Corner: String { case left, right, free }

    /// The mini player is showing (persisted across launches).
    @Published private(set) var isMini: Bool
    /// The full panel was opened from the mini player, anchored to its corner; collapsing returns to it.
    @Published private(set) var expandedFromMini = false

    private var panel: TextifyPanel?
    private var keyMonitor: Any?
    private var settingFrame = false
    /// Snapshot/test runs share the app's preferences — never change the user's saved layout from them.
    private let persist = ProcessInfo.processInfo.environment["TEXTIFY_SNAPSHOT_DIR"] == nil

    private enum Keys {
        static let mini = "miniMode", corner = "miniCorner", miniOrigin = "miniOrigin", fullOrigin = "fullOrigin"
    }

    /// Where the mini player lives: a bottom corner, or a free spot the user dragged it to.
    private(set) var miniCorner: Corner
    private var miniOrigin: NSPoint?

    override init() {
        let d = UserDefaults.standard
        isMini = d.bool(forKey: Keys.mini)
        miniCorner = Corner(rawValue: d.string(forKey: Keys.corner) ?? "") ?? .right
        miniOrigin = d.string(forKey: Keys.miniOrigin).map(NSPointFromString)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        // Re-dock on every show: the Dock or screen may have changed since.
        if isMini { setFrame(miniFrame(), animate: false) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    // MARK: - Mini player

    /// ⌘M: full panel ↔ mini player.
    func toggleMini() { isMini ? expand() : enterMini() }

    func enterMini() {
        let panel = self.panel ?? makePanel()
        if !isMini, !expandedFromMini { saveFullOrigin(panel.frame.origin) }
        TextifyViewModel.shared.showSettings = false
        expandedFromMini = false
        setMini(true)
        setFrame(miniFrame(), animate: true)
        show()
    }

    /// Opens the full panel from the mini player, growing up from the mini player's corner.
    func expand(showSettings: Bool = false) {
        guard isMini, let panel else { show(); return }
        let full = anchoredFullFrame(from: panel.frame, screen: panel.screen ?? NSScreen.main)
        expandedFromMini = true
        setMini(false)
        setFrame(full, animate: true)
        if showSettings { TextifyViewModel.shared.showSettings = true }
        show()
    }

    /// Moves the mini player tight into a bottom corner.
    func snap(to corner: Corner) {
        guard isMini else { return }
        save(corner: corner)
        setFrame(miniFrame(), animate: true)
    }

    /// Called when the user lets go of the mini player after dragging it. Near a bottom corner
    /// (or dropped into the Dock's row) it sticks tight to that corner; elsewhere it stays put.
    func miniDragEnded() {
        guard isMini, let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let f = panel.frame
        let left = miniFrame(corner: .left, screen: screen), right = miniFrame(corner: .right, screen: screen)
        let dLeft = hypot(f.minX - left.minX, f.minY - left.minY)
        let dRight = hypot(f.minX - right.minX, f.minY - right.minY)
        let inDockRow = f.minY < screen.visibleFrame.minY + 24
        if dLeft < 180 || dRight < 180 || inDockRow {
            snap(to: (inDockRow ? f.midX < screen.frame.midX : dLeft <= dRight) ? .left : .right)
        } else {
            miniOrigin = f.origin
            save(corner: .free)
            if persist { UserDefaults.standard.set(NSStringFromPoint(f.origin), forKey: Keys.miniOrigin) }
        }
    }

    /// Mini player frame: tight in the chosen bottom corner, vertically centered on the Dock's row
    /// (beside the Dock, not under it). Works with the Dock at the bottom, on a side, or hidden.
    func miniFrame(corner: Corner? = nil, screen: NSScreen? = nil) -> NSRect {
        let size = Self.miniSize
        let corner = corner ?? miniCorner
        let screen = screen ?? panel?.screen ?? NSScreen.main
        guard let screen else { return NSRect(origin: .zero, size: size) }
        let vf = screen.visibleFrame, sf = screen.frame
        if corner == .free, let miniOrigin {
            return clamp(NSRect(origin: miniOrigin, size: size), to: sf)
        }
        let dockRow = vf.minY - sf.minY  // Dock height when it sits at the bottom, else ~0
        let y = sf.minY + (dockRow >= size.height + 8 ? ((dockRow - size.height) / 2).rounded() : 6)
        let margin: CGFloat = 8
        let x = corner == .left ? vf.minX + margin : vf.maxX - size.width - margin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The full panel sitting just above the Dock's row, aligned with the mini player's outer edge.
    private func anchoredFullFrame(from mini: NSRect, screen: NSScreen?) -> NSRect {
        let size = Self.size
        guard let screen else { return NSRect(origin: mini.origin, size: size) }
        let vf = screen.visibleFrame
        let onRight = mini.midX > screen.frame.midX
        let x = onRight ? mini.maxX - size.width : mini.minX
        let y = max(vf.minY + 6, mini.minY)
        return clamp(NSRect(x: x, y: y, width: size.width, height: size.height), to: vf)
    }

    private func clamp(_ r: NSRect, to bounds: NSRect) -> NSRect {
        var r = r
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    private func setMini(_ on: Bool) {
        isMini = on
        if persist { UserDefaults.standard.set(on, forKey: Keys.mini) }
    }

    private func save(corner: Corner) {
        miniCorner = corner
        if persist { UserDefaults.standard.set(corner.rawValue, forKey: Keys.corner) }
    }

    private func saveFullOrigin(_ p: NSPoint) {
        if persist { UserDefaults.standard.set(NSStringFromPoint(p), forKey: Keys.fullOrigin) }
    }

    private func setFrame(_ frame: NSRect, animate: Bool) {
        guard let panel else { return }
        settingFrame = true
        panel.setFrame(frame, display: true, animate: animate && panel.isVisible)
        settingFrame = false
    }

    // MARK: - Window delegate

    func windowDidBecomeKey(_ notification: Notification) {
        TextifyViewModel.shared.panelFocusChanged(isKey: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        TextifyViewModel.shared.panelFocusChanged(isKey: false)
    }

    func windowDidMove(_ notification: Notification) {
        // Remember where the user keeps the full panel (not the temporary spot it opens at from the mini player).
        guard !settingFrame, !isMini, !expandedFromMini, let panel else { return }
        saveFullOrigin(panel.frame.origin)
    }

    // MARK: - Setup

    private func makePanel() -> TextifyPanel {
        let panel = TextifyPanel(
            contentRect: NSRect(origin: .zero, size: isMini ? Self.miniSize : Self.size),
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

        let host = NSHostingView(rootView: PanelRootView()
            .environmentObject(TextifyViewModel.shared)
            .environmentObject(self))
        host.sizingOptions = []  // the panel's size is ours to set (full ↔ mini)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel

        if isMini {
            panel.setFrame(miniFrame(screen: NSScreen.main), display: false)
        } else if let s = UserDefaults.standard.string(forKey: Keys.fullOrigin) {
            panel.setFrameOrigin(NSPointFromString(s))
        } else if !panel.setFrameUsingName("TextifyPanel"), let screen = NSScreen.main {
            // First launch: near the top-right of the screen.
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - Self.size.width - 24, y: vf.maxY - Self.size.height - 24))
        }
        if !isMini { panel.setContentSize(Self.size) }
        panel.delegate = self

        installKeyMonitor()
        return panel
    }

    /// Intercepts ⌘V, ⌘M, ⌘W, ⌘, and Esc while the panel is key. Everything else (⌘C, ⌘A…) flows normally.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let vm = TextifyViewModel.shared
            let key = event.charactersIgnoringModifiers?.lowercased()

            if event.keyCode == 53 { // Escape
                vm.handleEscape()
                return nil
            }
            guard mods == .command else { return event }
            switch key {
            case "v": vm.processClipboard()
            case "m": self.toggleMini()
            case "w": self.hide()
            case ",": self.isMini ? self.expand(showSettings: true) : vm.showSettings.toggle()
            default: return event
            }
            return nil
        }
    }
}

/// Switches between the full panel and the mini player.
struct PanelRootView: View {
    @EnvironmentObject var panel: FloatingPanelManager

    var body: some View {
        if panel.isMini { MiniPlayerView() } else { ContentView() }
    }
}
