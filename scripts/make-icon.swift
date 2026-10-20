import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"],
             256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.23, blue: 0.22, alpha: 1),
                                  ending: NSColor(srgbRed: 0.06, green: 0.12, blue: 0.13, alpha: 1))!
        gradient.draw(in: background, angle: -60)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor(srgbRed: 0.3, green: 0.91, blue: 0.73, alpha: 1).cgColor)
        context.setLineWidth(38)
        context.stroke(CGRect(x: 410, y: 282, width: 354, height: 425))
        let coral = NSColor(srgbRed: 1, green: 0.38, blue: 0.38, alpha: 1).cgColor
        context.setStrokeColor(coral)
        context.setFillColor(coral)
        context.setLineWidth(54)
        context.move(to: CGPoint(x: 250, y: 303))
        context.addLine(to: CGPoint(x: 522, y: 575))
        context.strokePath()
        context.move(to: CGPoint(x: 608, y: 661))
        context.addLine(to: CGPoint(x: 454, y: 615))
        context.addLine(to: CGPoint(x: 562, y: 507))
        context.closePath()
        context.fillPath()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        // Modern ICNS entries contain PNG data. Write the container directly so the
        // build also works where iconutil's image conversion service is unavailable.
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(bigEndian(png.count + 8))
        chunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: directory.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
