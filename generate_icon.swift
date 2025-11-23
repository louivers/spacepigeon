import Cocoa

let size = NSSize(width: 512, height: 512)
let image = NSImage(size: size)

image.lockFocus()

// Background Circle
let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 512, height: 512))
NSColor.systemBlue.setFill()
path.fill()

// Text "SP"
let text = "SP" as NSString
let font = NSFont.systemFont(ofSize: 256, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let textSize = text.size(withAttributes: attrs)
let textRect = NSRect(
    x: (512 - textSize.width) / 2,
    y: (512 - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

// Save to PNG
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: "icon.png")
    try? pngData.write(to: url)
}

