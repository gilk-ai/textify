import AppKit

/// Entry point. TEXTIFY is a floating panel with a Dock icon and a menu-bar item
/// (the Dock icon can be turned off in Settings, making it menu-bar only).
@main
enum TextifyMain {
    static func main() {
        // Headless test hooks: `Textify --ocr <image>` / `Textify --ocr-clipboard`.
        if CommandLineTools.runIfRequested() { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        DockPresence.apply()
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
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

    /// Clicking the Dock icon (or opening the app again) brings the panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FloatingPanelManager.shared.show()
        return false
    }

    // MARK: - Main menu (shown in the menu bar while TEXTIFY is the active app)

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "TEXTIFY")
        appMenu.addItem(item("About TEXTIFY", #selector(showAbout), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide TEXTIFY", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TEXTIFY", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu))

        let file = NSMenu(title: "File")
        file.addItem(item("Open Image…", #selector(openImage), "o"))
        file.addItem(item("Extract Text from Clipboard", #selector(extractClipboard), ""))
        main.addItem(submenu(file))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit))

        let window = NSMenu(title: "Window")
        window.addItem(item("Show TEXTIFY", #selector(showPanel), "0"))
        window.addItem(item("Hide Panel", #selector(hidePanel), "w"))
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Screenshots to text, on your Mac.\nNothing leaves your computer.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                      .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    @objc private func openSettings() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.showSettings = true
    }

    @objc private func openImage() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.openImageFile()
    }

    @objc private func extractClipboard() {
        FloatingPanelManager.shared.show()
        TextifyViewModel.shared.processClipboard()
    }

    @objc private func showPanel() { FloatingPanelManager.shared.show() }
    @objc private func hidePanel() { FloatingPanelManager.shared.hide() }
}

/// Whether TEXTIFY shows a Dock icon (default) or runs from the menu bar only.
@MainActor
enum DockPresence {
    private static let key = "showInDock"

    static var showInDock: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); apply() }
    }

    static func apply() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        // Switching policy can deactivate the app; keep the panel available.
        if NSApp.isRunning { DispatchQueue.main.async { FloatingPanelManager.shared.show() } }
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
