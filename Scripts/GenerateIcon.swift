import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.035, green: 0.17, blue: 0.18, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(red: 0.38, green: 0.94, blue: 0.79, alpha: 1).setStroke()
let chip = NSBezierPath(roundedRect: NSRect(x: 294, y: 294, width: 436, height: 436), xRadius: 70, yRadius: 70)
chip.lineWidth = 28
chip.stroke()
for p in stride(from: 380, through: 644, by: 88) {
    for (a,b,c,d) in [(p,210,p,294),(p,730,p,814),(210,p,294,p),(730,p,814,p)] {
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x:a,y:b)); pin.line(to:NSPoint(x:c,y:d)); pin.lineWidth = 24; pin.lineCapStyle = .round; pin.stroke()
    }
}
NSColor.white.setFill()
for x in [400, 540] { for y in [400, 540] {
    NSBezierPath(roundedRect:NSRect(x:x,y:y,width:84,height:84),xRadius:18,yRadius:18).fill()
}}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "LocalModels/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
