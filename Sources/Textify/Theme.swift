import SwiftUI
import AppKit

enum Theme {
    static let background = Color(hex: 0x15191C)
    static let surface = Color(hex: 0x242B30)
    static let accent = Color(hex: 0xB6F34A)
    static let text = Color.white
    static let secondary = Color(hex: 0xAAB3B9)
    static let error = Color(hex: 0xFF6B6B)
    static let warning = Color(hex: 0xF5C451)

    static let nsSurface = NSColor(hex: 0x242B30)
    static let nsAccent = NSColor(hex: 0xB6F34A)

    static let corner: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Lets the user drag the borderless panel from any non-interactive area (e.g. the header).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
