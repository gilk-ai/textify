import SwiftUI

/// Compact cards above the extracted text for things TEXTIFY recognized:
/// a QR code, a calendar event, a receipt. Each offers one or two direct actions.
struct DetectionCards: View {
    @EnvironmentObject var vm: TextifyViewModel

    var body: some View {
        VStack(spacing: 6) {
            if let code = vm.codes.first {
                DetectionCard(symbol: code.kind.isWiFi ? "wifi" : "qrcode", title: code.title, subtitle: code.subtitle) {
                    CardButton(symbol: "doc.on.doc", help: code.kind.isWiFi ? "Copy password" : "Copy") { vm.copyCode(code) }
                    if case .link = code.kind {
                        CardButton(symbol: "arrow.up.right.square", help: "Open link") { vm.openCode(code) }
                    }
                }
            }
            if let event = vm.events.first {
                DetectionCard(symbol: "calendar.badge.plus", title: event.title,
                              subtitle: event.whenText + (vm.events.count > 1 ? "  +\(vm.events.count - 1) more" : "")) {
                    CardTextButton(title: "Add to Calendar") { vm.addToCalendar(event) }
                }
            }
            if let receipt = vm.receipt {
                DetectionCard(symbol: "receipt", title: receipt.vendor, subtitle: receipt.summary) {
                    if vm.receiptLedger != nil {
                        CardTextButton(title: "Logged ✓") { vm.revealLedger() }
                            .help("Added to \(ExpenseLedger.fileName). Click to show it in Finder.")
                    } else {
                        CardTextButton(title: "Log expense") { vm.addReceiptToLedger() }
                            .help("Add date, vendor, total and VAT to \(ExpenseLedger.fileName) in the save folder")
                    }
                }
            }
        }
    }
}

private extension DetectedCode.Kind {
    var isWiFi: Bool { if case .wifi = self { return true }; return false }
}

struct DetectionCard<Actions: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 4)
            HStack(spacing: 4) { actions() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
    }
}

struct CardButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.background : Theme.accent)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.accent : Theme.background))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct CardTextButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.background : Theme.accent)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.accent : Theme.background))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
