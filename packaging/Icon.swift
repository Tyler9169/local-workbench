import AppKit

let output = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
func draw(size: Int, path: String) {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    NSColor(calibratedRed: 0.09, green: 0.23, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 195, yRadius: 195).fill()
    NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.91, alpha: 1).setStroke()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 245, y: 650))
    mark.line(to: NSPoint(x: 340, y: 375))
    mark.line(to: NSPoint(x: 490, y: 602))
    mark.line(to: NSPoint(x: 625, y: 375))
    mark.line(to: NSPoint(x: 755, y: 650))
    mark.lineWidth = 66
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.stroke()
    NSColor(calibratedRed: 0.79, green: 0.90, blue: 0.56, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 740, y: 305, width: 66, height: 66)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for s in sizes {
    draw(size: s, path: "\(output)/icon_\(s)x\(s).png")
    draw(size: s*2, path: "\(output)/icon_\(s)x\(s)@2x.png")
}
