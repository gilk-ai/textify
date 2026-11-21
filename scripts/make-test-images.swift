// Renders sample images for testing OCR: swift scripts/make-test-images.swift <outdir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "test-images")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ name: String, _ paragraphs: [String], rtl: Bool = false, size: NSSize = NSSize(width: 900, height: 500), blank: Bool = false) {
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    if !blank {
        let style = NSMutableParagraphStyle()
        style.alignment = rtl ? .right : .left
        style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        style.paragraphSpacing = 22
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black, .paragraphStyle: style]
        NSAttributedString(string: paragraphs.joined(separator: "\n"), attributes: attrs)
            .draw(in: NSRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}

render("english.png", ["The quick brown fox jumps over the lazy dog.", "Second line of the same paragraph here."])
render("multi-paragraph.png", ["First paragraph starts here and wraps onto a second line because it is long enough.", "", "Second paragraph after a gap.", "", "Third paragraph: 42 items, $19.99 each."], size: NSSize(width: 900, height: 600))
render("hebrew.png", ["שלום עולם, זהו מבחן של זיהוי טקסט.", "שורה שנייה בעברית עם מספר 2026."], rtl: true)
render("mixed.png", ["Meeting notes — Monday", "פגישה עם הצוות בשעה עשר", "Action items: ship TEXTIFY"])
render("invoice.png", ["INVOICE #4471", "Acme Corporation — Design Services", "Website redesign: $1,200.00", "Hosting (12 months): $80.00", "Total due: $1,280.00 by December 1, 2026"], size: NSSize(width: 900, height: 420))
render("recipe.png", ["Grandma's Lemon Olive Oil Cake", "Ingredients: 3 eggs, 1 cup sugar, 2 lemons, 1/2 cup olive oil, 1.5 cups flour", "Bake at 175°C for 40 minutes until golden."], size: NSSize(width: 900, height: 360))
// Tables: gridded, borderless, and a right-to-left Hebrew table (first column on the right).
func renderTable(_ name: String, _ rows: [[String]], grid: Bool, colW: [CGFloat], rtl: Bool = false) {
    let rowH: CGFloat = 50, pad: CGFloat = 40
    let size = NSSize(width: colW.reduce(0, +) + 2 * pad, height: CGFloat(rows.count) * rowH + 2 * pad)
    let img = NSImage(size: size); img.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    for (r, row) in rows.enumerated() {
        let cells = rtl ? Array(row.reversed()) : row
        let widths = rtl ? Array(colW.reversed()) : colW
        var x = pad
        let y = size.height - pad - CGFloat(r + 1) * rowH
        for (c, cell) in cells.enumerated() {
            let rect = NSRect(x: x, y: y, width: widths[c], height: rowH)
            if grid {
                if r == 0 { NSColor(white: 0.92, alpha: 1).setFill(); rect.fill() }
                NSColor.gray.setStroke(); NSBezierPath(rect: rect).stroke()
            }
            let style = NSMutableParagraphStyle(); style.alignment = rtl ? .right : .left
            NSAttributedString(string: cell, attributes: [.font: r == 0 ? NSFont.boldSystemFont(ofSize: 22) : NSFont.systemFont(ofSize: 22),
                                                          .foregroundColor: NSColor.black, .paragraphStyle: style])
                .draw(in: rect.insetBy(dx: 12, dy: 12))
            x += widths[c]
        }
    }
    img.unlockFocus()
    try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}
let sales = [["Product", "Region", "Units", "Price", "Share"],
             ["Laptop Pro", "North", "120", "1,299.00", "12%"],
             ["Monitor 27", "South", "85", "349.50", "8.5%"],
             ["Keyboard", "East", "430", "79.99", "41%"],
             ["Mouse", "West", "0512", "24.90", "38.5%"]]
renderTable("table-grid.png", sales, grid: true, colW: [200, 140, 110, 150, 110])
renderTable("table-plain.png", sales, grid: false, colW: [200, 140, 110, 150, 110])
renderTable("table-hebrew.png", [["מוצר", "אזור", "כמות", "מחיר"], ["מחשב נייד", "צפון", "120", "1,299.00"], ["מסך", "דרום", "85", "349.50"]],
            grid: true, colW: [200, 140, 110, 150], rtl: true)
// A table whose title row spans all columns (merged cell).
do {
    let w: CGFloat = 480, rowH: CGFloat = 50, pad: CGFloat = 40
    let size = NSSize(width: w + 2 * pad, height: 4 * rowH + 2 * pad)
    let img = NSImage(size: size); img.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    func cell(_ t: String, _ x: CGFloat, _ r: Int, _ cw: CGFloat, bold: Bool = false) {
        let rect = NSRect(x: pad + x, y: size.height - pad - CGFloat(r + 1) * rowH, width: cw, height: rowH)
        NSColor.gray.setStroke(); NSBezierPath(rect: rect).stroke()
        NSAttributedString(string: t, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: 22) : NSFont.systemFont(ofSize: 22)])
            .draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 12))
    }
    cell("Q1 Sales Report", 0, 0, w, bold: true)
    cell("Team", 0, 1, 200, bold: true); cell("Jan", 200, 1, 140, bold: true); cell("Feb", 340, 1, 140, bold: true)
    cell("Alpha", 0, 2, 200); cell("1,200", 200, 2, 140); cell("1,450", 340, 2, 140)
    cell("Beta", 0, 3, 200); cell("980", 200, 3, 140); cell("1,010", 340, 3, 140)
    img.unlockFocus()
    try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent("table-merged.png"))
    print("wrote table-merged.png")
}
render("blank.png", [], blank: true)
