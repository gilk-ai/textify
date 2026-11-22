import AppKit
import SwiftUI

/// The mini player: a slim bar that docks in a bottom corner beside the Dock.
/// Drop a screenshot on it or press ⌘V; it shows what was copied, and expands to the full panel when needed.
/// Drag it near a bottom corner (or into the Dock's row) and it snaps tight into that corner.
struct MiniPlayerView: View {
    @EnvironmentObject var vm: TextifyViewModel
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                headline
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsHitTesting(false)
            Spacer(minLength: 2)
            badges
            HStack(spacing: 2) {
                if vm.hasResult {
                    MiniButton(symbol: "doc.on.doc", help: "Copy again") { vm.copyToClipboard() }
                } else {
                    MiniButton(symbol: "doc.on.clipboard", help: "Extract text from the clipboard (⌘V)") { vm.processClipboard() }
                }
                MiniButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Expand (⌘M) · double-click the bar") {
                    FloatingPanelManager.shared.expand()
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MiniDragArea())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isTargeted ? Theme.accent : Color.white.opacity(0.10),
                                      lineWidth: isTargeted ? 2 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { ContentView.handleDrop($0, vm: vm) }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.15), value: vm.status)
    }

    @ViewBuilder private var headline: some View {
        HStack(spacing: 4) {
            switch vm.status {
            case .idle:
                Text(isTargeted ? "Drop to extract text" : "Drop a screenshot").foregroundStyle(Theme.text)
            case .processing:
                ProgressView().controlSize(.mini).tint(Theme.accent)
                Text("Reading text…").foregroundStyle(Theme.text)
            case .copied:
                Image(systemName: vm.saveError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(vm.saveError == nil ? Theme.accent : Theme.warning)
                Text(vm.saveError == nil ? vm.copiedMessage : "Copied · save failed")
                    .foregroundStyle(vm.saveError == nil ? Theme.accent : Theme.warning)
            case .copyFailed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text("Couldn't copy").foregroundStyle(Theme.warning)
            case .noText:
                Image(systemName: "eye.slash").foregroundStyle(Theme.warning)
                Text("No text found").foregroundStyle(Theme.warning)
            case .error:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.error)
                Text("Couldn't read that").foregroundStyle(Theme.error)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
    }

    /// Second line: a preview of what was copied, or a hint.
    private var detail: String {
        switch vm.status {
        case .idle: return vm.panelIsKey ? "or press ⌘V to paste one" : "or click here, then ⌘V"
        case .processing: return "On-device · nothing leaves your Mac"
        case .copied:
            let preview = vm.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let saved = vm.savedURL == nil ? "" : (vm.savedURL?.pathExtension == "xlsx" ? "Saved to Excel · " : "Saved · ")
            return saved + (preview.isEmpty ? "On the clipboard" : preview)
        case .copyFailed(let msg), .error(let msg): return msg
        case .noText: return "Try another screenshot"
        }
    }

    /// Small hints that the full panel has more (QR code, event, receipt, table).
    @ViewBuilder private var badges: some View {
        let symbols = [vm.codes.isEmpty ? nil : "qrcode",
                       vm.events.isEmpty ? nil : "calendar",
                       vm.receipt == nil ? nil : "receipt",
                       vm.tables.isEmpty ? nil : "tablecells"].compactMap { $0 }
        if !symbols.isEmpty {
            HStack(spacing: 3) {
                ForEach(symbols, id: \.self) { Image(systemName: $0) }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .help("More in the full panel — expand to see it")
            .onTapGesture { FloatingPanelManager.shared.expand() }
        }
    }
}

private struct MiniButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.background : Theme.accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.accent : Theme.surface))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The bar's background: drag to move (snaps into a corner on release), double-click to expand,
/// right-click for the menu.
private struct MiniDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { FloatingPanelManager.shared.expand(); return }
            window?.performDrag(with: event)  // returns when the drag ends
            FloatingPanelManager.shared.miniDragEnded()
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let m = NSMenu()
            func add(_ title: String, _ key: String = "", _ action: @escaping () -> Void) {
                let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
                m.addItem(item)
            }
            let p = FloatingPanelManager.shared, vm = TextifyViewModel.shared
            add("Expand", "m") { p.expand() }
            add("Extract Text from Clipboard", "v") { vm.processClipboard() }
            add("Open Image…") { vm.openImageFile() }
            m.addItem(.separator())
            add("Stick to Bottom-Left Corner") { p.snap(to: .left) }
            add("Stick to Bottom-Right Corner") { p.snap(to: .right) }
            m.addItem(.separator())
            if vm.hasResult { add("Clear") { vm.clear() } }
            add("Settings…", ",") { p.expand(showSettings: true) }
            add("Hide", "w") { p.hide() }
            return m
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
