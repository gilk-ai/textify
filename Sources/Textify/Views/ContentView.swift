import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: TextifyViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            header
            Group {
                if vm.showSettings {
                    SettingsView()
                } else if vm.hasResult {
                    ExtractedTextView()
                } else {
                    ImageDropZone(isTargeted: isTargeted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar()
        }
        .padding(14)
        .frame(width: FloatingPanelManager.size.width, height: FloatingPanelManager.size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(isTargeted ? Theme.accent : Color.white.opacity(0.08),
                                      lineWidth: isTargeted ? 2 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        // The whole panel accepts drops, so a new screenshot can replace an existing result.
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted, perform: handleDrop)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("TEXTIFY")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(2.5)
                .foregroundStyle(Theme.text)
            Spacer()
            HeaderButton(symbol: vm.showSettings ? "xmark" : "gearshape", help: "Settings (⌘,)") {
                vm.showSettings.toggle()
            }
            HeaderButton(symbol: "minus", help: "Hide (⌘W)") {
                FloatingPanelManager.shared.hide()
            }
        }
        .padding(.horizontal, 2)
        .background(WindowDragArea())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        vm.showSettings = false
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    if let url { vm.process(url: url) }
                    else { vm.status = .error("Couldn't read the dropped file.") }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in
                    if let data { vm.process(data: data) }
                    else { vm.status = .error("Couldn't read the dropped image.") }
                }
            }
            return true
        }
        vm.status = .error("Unsupported item. Drop a PNG, JPG, HEIC or TIFF image.")
        return false
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : Theme.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Theme.surface : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Bottom status line: processing / copied / errors.
struct StatusBar: View {
    @EnvironmentObject var vm: TextifyViewModel

    var body: some View {
        HStack(spacing: 6) {
            switch vm.status {
            case .idle:
                Image(systemName: "lock.shield").foregroundStyle(Theme.secondary)
                Text("On-device OCR · nothing leaves your Mac").foregroundStyle(Theme.secondary)
            case .processing:
                ProgressView().controlSize(.small).tint(Theme.accent)
                Text("Reading text…").foregroundStyle(Theme.secondary)
            case .copied:
                if let saveError = vm.saveError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text(saveError).foregroundStyle(Theme.warning)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text(vm.successMessage)
                        .foregroundStyle(Theme.accent).fontWeight(.semibold)
                }
                if !vm.tables.isEmpty, vm.savedURL?.pathExtension != "xlsx" {
                    Text("· table pastes as cells").foregroundStyle(Theme.secondary)
                }
                if vm.partiallyReadable {
                    Text("· some text may be unclear").foregroundStyle(Theme.warning)
                }
            case .copyFailed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(msg).foregroundStyle(Theme.warning)
            case .noText:
                Image(systemName: "eye.slash").foregroundStyle(Theme.warning)
                Text("No text found. Try another screenshot.").foregroundStyle(Theme.warning)
            case .error(let msg):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.error)
                Text(msg).foregroundStyle(Theme.error)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .lineLimit(2)
        .frame(minHeight: 18)
        .animation(.easeOut(duration: 0.15), value: vm.status)
    }
}
