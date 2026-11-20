// Draws the TEXTIFY app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSColor(srgbRed: 0x15/255, green: 0x19/255, blue: 0x1C/255, alpha: 1).setFill(); bg.fill()
    let acid = NSColor(srgbRed: 0xB6/255, green: 0xF3/255, blue: 0x4A/255, alpha: 1)

    // Viewfinder corners.
    let f = rect.insetBy(dx: rect.width * 0.2, dy: rect.width * 0.2)
    let L = f.width * 0.26, w = max(1, s * 0.035)
    let corners = NSBezierPath(); corners.lineWidth = w; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
    for (x, y, dx, dy) in [(f.minX, f.minY, 1.0, 1.0), (f.maxX, f.minY, -1.0, 1.0), (f.minX, f.maxY, 1.0, -1.0), (f.maxX, f.maxY, -1.0, -1.0)] {
        corners.move(to: NSPoint(x: x, y: y + dy * L)); corners.line(to: NSPoint(x: x, y: y)); corners.line(to: NSPoint(x: x + dx * L, y: y))
    }
    acid.setStroke(); corners.stroke()

    // Text lines.
    let lh = max(1, s * 0.045), gap = f.height * 0.17
    for (i, frac) in [0.78, 0.6, 0.7].enumerated() {
        let y = f.midY + gap - CGFloat(i) * gap - lh / 2
        let bar = NSBezierPath(roundedRect: NSRect(x: f.minX + f.width * 0.17, y: y, width: f.width * 0.66 * frac, height: lh), xRadius: lh / 2, yRadius: lh / 2)
        (i == 0 ? acid : NSColor.white.withAlphaComponent(0.9)).setFill(); bar.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
