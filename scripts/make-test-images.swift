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
render("blank.png", [], blank: true)
