// Draws the TEXTIFY app icon — a bold "T" inside a viewfinder, crossed by a glowing scan line.
//
//   swift scripts/make-icon.swift <out.iconset>            → all .icns sizes
//   swift scripts/make-icon.swift --preview <out.png>      → preview sheet (every size, light + dark)
//
// Every size is drawn from vectors (no downscaling), small sizes use a simplified, thicker design
// snapped to the pixel grid so they stay crisp.
import AppKit

// MARK: - Palette

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let acid = rgb(0xB6F34A)
let bgTop = rgb(0x2B333A), bgBottom = rgb(0x101315)

// MARK: - Shapes

/// macOS-style continuous-corner square ("squircle"), as a superellipse.
func squircle(_ r: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let p = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

// MARK: - Icon

/// Draws the icon into a `px`×`px` context. Design coordinates are 1024×1024, origin top-left.
func drawIcon(_ ctx: CGContext, px: Int) {
    let scale = CGFloat(px) / 1024
    let small = px <= 32
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: scale, y: -scale)

    /// Rounds a rect to whole device pixels (only matters for tiny sizes).
    func snap(_ r: CGRect) -> CGRect {
        guard px <= 64 else { return r }
        let k = scale
        let x0 = (r.minX * k).rounded() / k, y0 = (r.minY * k).rounded() / k
        let x1 = (r.maxX * k).rounded() / k, y1 = (r.maxY * k).rounded() / k
        return CGRect(x: x0, y: y0, width: max(x1 - x0, 1 / k), height: max(y1 - y0, 1 / k))
    }

    // Body: Apple's grid puts an 824pt shape on the 1024 canvas, with room for the drop shadow.
    let body = small ? CGRect(x: 64, y: 64, width: 896, height: 896) : CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    if !small {
        ctx.saveGState()
        // Shadow offset/blur are in device pixels and ignore our flipped transform: scale them, and
        // use a negative y so the shadow falls below the icon.
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape); ctx.setFillColor(bgBottom); ctx.fillPath()
        ctx.restoreGState()
    }

    // Graphite gradient + faint green glow in the middle.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bgTop, bgBottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: body.maxY), options: [])
    if !small {
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0xB6F34A, 0.16), rgb(0xB6F34A, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 560), endRadius: 380, options: [])
        // Top highlight for a little depth.
        let shine = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(gray: 1, alpha: 0.07), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: body.minY + 300), options: [])
    }
    ctx.restoreGState()

    if !small {
        // Hairline rim so the icon holds its edge on dark Docks.
        ctx.addPath(squircle(body.insetBy(dx: 2, dy: 2)))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(3); ctx.strokePath()
    }

    // Viewfinder corners.
    // Small: 192…832 is exactly pixels 3…13 at 16px and 6…26 at 32px.
    let finder = small ? CGRect(x: 192, y: 192, width: 640, height: 640) : CGRect(x: 248, y: 248, width: 528, height: 528)
    let arm: CGFloat = small ? 192 : 150, line: CGFloat = small ? 64 : 40
    ctx.setStrokeColor(acid); ctx.setLineWidth(line)
    ctx.setLineCap(small ? .square : .round); ctx.setLineJoin(small ? .miter : .round)
    if small {
        // Tiny sizes: each corner is two pixel-snapped rectangles, so edges land on whole pixels.
        let t = max(line, 1024 / CGFloat(px))  // at least one device pixel thick
        ctx.setFillColor(acid)
        for (x, y, right, down) in [(finder.minX, finder.minY, true, true), (finder.maxX, finder.minY, false, true),
                                    (finder.minX, finder.maxY, true, false), (finder.maxX, finder.maxY, false, false)] {
            let hx = right ? x : x - arm, vy = down ? y : y - arm
            let hy = down ? y : y - t, vx = right ? x : x - t
            ctx.fill(snap(CGRect(x: hx, y: hy, width: arm, height: t)))
            ctx.fill(snap(CGRect(x: vx, y: vy, width: t, height: arm)))
        }
    } else {
        let inset = line / 2
        let f = finder.insetBy(dx: inset, dy: inset)
        for (x, y, dx, dy) in [(f.minX, f.minY, 1.0, 1.0), (f.maxX, f.minY, -1.0, 1.0),
                               (f.minX, f.maxY, 1.0, -1.0), (f.maxX, f.maxY, -1.0, -1.0)] {
            ctx.move(to: CGPoint(x: x, y: y + dy * arm))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        ctx.strokePath()
    }

    // The "T".
    let white = CGColor(gray: 1, alpha: 1)
    let bar = snap(small ? CGRect(x: 340, y: 330, width: 344, height: 110) : CGRect(x: 372, y: 352, width: 280, height: 72))
    let stemW: CGFloat = small ? 120 : 80
    let stem = snap(CGRect(x: 512 - stemW / 2, y: bar.minY, width: stemW, height: (small ? 700 : 676) - bar.minY))
    ctx.setFillColor(white)
    let radius: CGFloat = small ? 0 : 12
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.addPath(CGPath(roundedRect: stem, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // Scan line crossing the T, with a soft glow (no glow at tiny sizes).
    if !small {
        let y: CGFloat = 556, h: CGFloat = px <= 64 ? 28 : 18
        let scan = CGRect(x: 300, y: y - h / 2, width: 424, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 36 * scale, color: rgb(0xB6F34A, 0.9))
        ctx.setFillColor(acid)
        ctx.addPath(CGPath(roundedRect: scan, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)); ctx.fillPath()
        ctx.restoreGState()
        // Text "below" the scan line has been read: tint the lower stem green.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: y + h / 2, width: 1024, height: 1024))
        ctx.setFillColor(rgb(0xB6F34A, 0.9))
        ctx.addPath(CGPath(roundedRect: stem, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    gctx.cgContext.setShouldAntialias(true)
    gctx.cgContext.interpolationQuality = .high
    drawIcon(gctx.cgContext, px: px)
    return rep
}

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--preview" {
    // Sheet: every size at 1:1 on a light and a dark strip.
    let sizes = [512, 256, 128, 64, 32, 16]
    let width = sizes.reduce(0, +) + 40 * (sizes.count + 1)
    let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 2 * 512 + 120, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: sheet)!
    let c = g.cgContext
    c.setFillColor(rgb(0xECECEC)); c.fill(CGRect(x: 0, y: 572, width: width, height: 572))
    c.setFillColor(rgb(0x1E1E1E)); c.fill(CGRect(x: 0, y: 0, width: width, height: 572))
    for strip in [0, 572] {
        var x = 40
        for s in sizes {
            if let img = render(s).cgImage { c.draw(img, in: CGRect(x: x, y: strip + 30, width: s, height: s)) }
            x += s + 40
        }
    }
    try! sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
} else {
    let out = URL(fileURLWithPath: args[1])
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try! render(base).representation(using: .png, properties: [:])!
            .write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
        try! render(base * 2).representation(using: .png, properties: [:])!
            .write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
}
