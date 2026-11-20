import SwiftUI

/// Empty-state drop target.
/// - Focused panel: "Press ⌘V" (accent). Unfocused: "Click here, then press ⌘V".
/// - Clicking the zone opens a file picker, except for the click that only focuses the panel.
/// - The ⌘V key caps are also a clickable Paste button.
struct ImageDropZone: View {
    @EnvironmentObject var vm: TextifyViewModel
    let isTargeted: Bool
    @State private var hovering = false

    private var highlighted: Bool { isTargeted || hovering }
    private var processing: Bool { vm.status == .processing }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(highlighted ? 0.18 : 0.10))
                    .frame(width: 76, height: 76)
                if processing {
                    ProgressView().controlSize(.large).tint(Theme.accent)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(spacing: 8) {
                Text(processing ? "Reading text…" : "Drop screenshot here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                pasteHint
                Text("or click to choose a file")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface.opacity(highlighted ? 1 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(highlighted ? Theme.accent : Theme.secondary.opacity(0.35))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // A click that merely brought the panel into focus shouldn't open a file picker.
            guard !vm.panelJustBecameKey else { return }
            vm.openImageFile()
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .animation(.easeOut(duration: 0.15), value: vm.panelIsKey)
    }

    /// Clickable "⌘ V" hint whose wording depends on whether the panel has keyboard focus.
    private var pasteHint: some View {
        Button { vm.processClipboard() } label: {
            HStack(spacing: 4) {
                Text(vm.panelIsKey ? "Press" : "Click here, then press")
                KeyCap("⌘", active: vm.panelIsKey)
                KeyCap("V", active: vm.panelIsKey)
            }
            .font(.system(size: 12, weight: vm.panelIsKey ? .semibold : .regular))
            .foregroundStyle(vm.panelIsKey ? Theme.accent : Theme.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.background.opacity(0.5)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Extract text from the image on the clipboard")
    }
}

struct KeyCap: View {
    let key: String
    var active = false
    init(_ key: String, active: Bool = false) { self.key = key; self.active = active }
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? Theme.background : Theme.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(active ? Theme.accent : Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(active ? 0 : 0.12)))
    }
}
