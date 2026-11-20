import AppKit
import Carbon.HIToolbox

/// Global shortcut choices offered in Settings.
enum HotKeyOption: String, CaseIterable, Identifiable {
    case cmdShiftV
    case ctrlOptCmdV
    case ctrlShiftT
    case disabled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cmdShiftV: return "⌘⇧V"
        case .ctrlOptCmdV: return "⌃⌥⌘V"
        case .ctrlShiftT: return "⌃⇧T"
        case .disabled: return "Disabled"
        }
    }

    /// (virtual key code, Carbon modifier mask)
    var carbon: (UInt32, UInt32)? {
        switch self {
        case .cmdShiftV: return (UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey))
        case .ctrlOptCmdV: return (UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey | cmdKey))
        case .ctrlShiftT: return (UInt32(kVK_ANSI_T), UInt32(controlKey | shiftKey))
        case .disabled: return nil
        }
    }

    static let defaultsKey = "globalHotKey"

    static var current: HotKeyOption {
        get { HotKeyOption(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .cmdShiftV }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Registers a single system-wide hotkey via Carbon. Needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onTrigger: (() -> Void)?

    /// Returns false if the shortcut could not be registered (e.g. taken by another app).
    @discardableResult
    func register(_ option: HotKeyOption) -> Bool {
        unregister()
        guard let (key, mods) = option.carbon else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5458_5446), id: 1) // 'TXTF'
        let status = RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
