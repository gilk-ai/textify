import SwiftUI
import AppKit

/// Shows the extracted text with Copy / Clear / Re-scan controls.
struct ExtractedTextView: View {
    @EnvironmentObject var vm: TextifyViewModel

    var body: some View {
        VStack(spacing: 10) {
            DetectionCards()
            ZStack {
                SelectableTextView(text: vm.text)
                if vm.status == .processing {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.background.opacity(0.6))
                    ProgressView().tint(Theme.accent)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                PillButton(title: "Copy", symbol: "doc.on.doc", primary: true) { vm.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                PillButton(title: "Clear", symbol: "xmark", primary: false) { vm.clear() }
                Spacer()
                if vm.savedURL != nil {
                    HeaderButton(symbol: "doc.text.magnifyingglass", help: "Show saved file in Finder") { vm.revealSavedFile() }
                }
                HeaderButton(symbol: "arrow.clockwise", help: "Re-scan image") { vm.rescan() }
                Text("\(vm.text.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

struct PillButton: View {
    let title: String
    let symbol: String
    let primary: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary ? Theme.background : Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(primary ? Theme.accent.opacity(hovering ? 0.85 : 1)
                                           : Theme.surface.opacity(hovering ? 1 : 0.8))
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// Read-only, selectable NSTextView. Each paragraph uses the natural writing direction,
/// so Hebrew paragraphs render right-to-left and English left-to-right.
struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.selectedTextAttributes = [.backgroundColor: Theme.nsAccent.withAlphaComponent(0.35)]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.textStorage?.setAttributedString(Self.attributed(text))
        tv.scroll(.zero)
    }

    static func attributed(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 13)
        let paragraphs = text.components(separatedBy: "\n")
        for (i, para) in paragraphs.enumerated() {
            let style = NSMutableParagraphStyle()
            let rtl = TextLayout.isPredominantlyRTL(para)
            style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
            style.alignment = rtl ? .right : .left
            style.lineSpacing = 2
            let line = para + (i < paragraphs.count - 1 ? "\n" : "")
            result.append(NSAttributedString(string: line, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
            ]))
        }
        return result
    }
}
