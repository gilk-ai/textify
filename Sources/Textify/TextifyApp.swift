import AppKit

/// Entry point. TEXTIFY runs as a menu-bar accessory (no Dock icon) with a floating panel.
@main
enum TextifyMain {
    static func main() {
        // Headless test hooks: `Textify --ocr <image>` / `Textify --ocr-clipboard`.
        if CommandLineTools.runIfRequested() { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        menuBar = MenuBarController()

        HotKeyManager.shared.onTrigger = {
            Task { @MainActor in
                FloatingPanelManager.shared.show()
                TextifyViewModel.shared.processClipboard()
            }
        }
        HotKeyManager.shared.register(HotKeyOption.current)

        FloatingPanelManager.shared.show()
        DebugSnapshots.runIfRequested()
    }

    /// Reopening the app (e.g. double-clicking it again) brings the panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FloatingPanelManager.shared.show()
        return false
    }

    /// Hidden main menu so standard key equivalents (⌘C, ⌘A, ⌘Q) work in the panel.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit TEXTIFY", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

/// Menu-bar status item.
@MainActor
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "TEXTIFY")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(makeItem("Show TEXTIFY", #selector(showPanel), ""))
        menu.addItem(makeItem("Extract Text from Clipboard", #selector(processClipboard), ""))
        menu.addItem(makeItem("Open Image…", #selector(openImage), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit TEXTIFY", #selector(quit), "q"))
        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func showPanel() { FloatingPanelManager.shared.show() }

    @objc private func processClipboard() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.processClipboard()
    }

    @objc private func openImage() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.openImageFile()
    }

    @objc private func openSettings() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.showSettings = true
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
