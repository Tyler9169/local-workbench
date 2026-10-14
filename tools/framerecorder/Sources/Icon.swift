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
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect:NSRect(x:80,y:80,width:864,height:864),xRadius:195,yRadius:195).fill()
    NSColor(calibratedRed:1,green:0.83,blue:0.18,alpha:1).setStroke()
    let frame=NSBezierPath(roundedRect:NSRect(x:240,y:300,width:544,height:424),xRadius:20,yRadius:20)
    frame.lineWidth=34;frame.stroke()
    NSColor(calibratedRed:1,green:0.83,blue:0.18,alpha:1).setFill()
    for x in [240,784] {for y in [300,724] {NSBezierPath(rect:NSRect(x:x-30,y:y-30,width:60,height:60)).fill()}}
    NSColor.systemRed.setFill()
    NSBezierPath(ovalIn:NSRect(x:425,y:425,width:174,height:174)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for s in sizes {
    draw(size: s, path: "\(output)/icon_\(s)x\(s).png")
    draw(size: s*2, path: "\(output)/icon_\(s)x\(s)@2x.png")
}
