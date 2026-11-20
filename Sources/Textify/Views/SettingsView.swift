import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var hotKey = HotKeyOption.current
    @State private var hotKeyFailed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hebrewEnabled = HebrewOCRService.isEnabled
    private let hebrewAvailable = HebrewOCRService.isAvailable

    var body: some View {
        ScrollView(showsIndicators: false) { settingsContent }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Global shortcut") {
                Picker("", selection: $hotKey) {
                    ForEach(HotKeyOption.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: hotKey) { _, newValue in
                    HotKeyOption.current = newValue
                    hotKeyFailed = !HotKeyManager.shared.register(newValue)
                }
                Text(hotKeyFailed
                     ? "That shortcut is in use by another app. Pick another."
                     : "Shows TEXTIFY and extracts text from the clipboard image from anywhere. ⌘⇧V overrides “Paste and Match Style” in other apps.")
                    .font(.system(size: 10))
                    .foregroundStyle(hotKeyFailed ? Theme.error : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.system(size: 10)).foregroundStyle(Theme.error)
                }
            }

            section("Hebrew text") {
                if hebrewAvailable {
                    Toggle("Read Hebrew (local Tesseract engine)", isOn: $hebrewEnabled)
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .onChange(of: hebrewEnabled) { _, on in HebrewOCRService.isEnabled = on }
                } else {
                    Text("Apple's OCR doesn't support Hebrew. To enable it offline, run in Terminal:")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("brew install tesseract tesseract-lang")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                }
            }

            section("Shortcuts") {
                VStack(alignment: .leading, spacing: 4) {
                    row("⌘V", "Extract text from clipboard image")
                    row("⌘C", "Copy selected text")
                    row("Esc", "Clear result / hide")
                    row("⌘W", "Hide panel")
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)
            content()
        }
    }

    private func row(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent).frame(width: 34, alignment: .leading)
            Text(desc).foregroundStyle(Theme.secondary).font(.system(size: 11))
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item. Move TEXTIFY.app to /Applications first."
        }
    }
}
