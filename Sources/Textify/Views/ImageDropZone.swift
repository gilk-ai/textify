import SwiftUI

/// Empty-state drop target. Clicking opens a file picker.
struct ImageDropZone: View {
    @EnvironmentObject var vm: TextifyViewModel
    let isTargeted: Bool
    @State private var hovering = false

    private var highlighted: Bool { isTargeted || hovering }

    var body: some View {
        Button { vm.openImageFile() } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(highlighted ? 0.18 : 0.10))
                        .frame(width: 76, height: 76)
                    if vm.status == .processing {
                        ProgressView().controlSize(.large).tint(Theme.accent)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(Theme.accent)
                    }
                }
                VStack(spacing: 6) {
                    Text(vm.status == .processing ? "Reading text…" : "Drop screenshot here")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 4) {
                        Text("Or press")
                        KeyCap("⌘")
                        KeyCap("V")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
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
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)))
    }
}
