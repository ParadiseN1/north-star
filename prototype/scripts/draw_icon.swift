import AppKit

// Vector master for the app icon. Render each resolution directly for sharp edges.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = destination.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func render(_ pixels: Int) -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 22,
                      color: color(0.13, 0.20, 0.16, 0.18))
    context.setFillColor(color(0.974, 0.979, 0.959))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let tileGradient = CGGradient(colorsSpace: colorSpace,
        colors: [color(0.943, 0.955, 0.923), color(0.996, 0.996, 0.984)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 100),
                               end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(0.66, 0.72, 0.64, 0.28))
    context.setLineWidth(1.5)
    context.strokePath()

    // Four concave rays, with the longer northern point carrying the direction.
    let star = CGMutablePath()
    star.move(to: CGPoint(x: 512, y: 812))
    star.addCurve(to: CGPoint(x: 778, y: 506),
                  control1: CGPoint(x: 549, y: 583), control2: CGPoint(x: 584, y: 541))
    star.addCurve(to: CGPoint(x: 512, y: 228),
                  control1: CGPoint(x: 584, y: 473), control2: CGPoint(x: 549, y: 435))
    star.addCurve(to: CGPoint(x: 246, y: 506),
                  control1: CGPoint(x: 475, y: 435), control2: CGPoint(x: 440, y: 473))
    star.addCurve(to: CGPoint(x: 512, y: 812),
                  control1: CGPoint(x: 440, y: 541), control2: CGPoint(x: 475, y: 583))
    star.closeSubpath()
    context.saveGState()
    context.addPath(star)
    context.clip()
    let starGradient = CGGradient(colorsSpace: colorSpace,
        colors: [color(0.145, 0.302, 0.243), color(0.259, 0.443, 0.353)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(starGradient, start: CGPoint(x: 700, y: 240),
                               end: CGPoint(x: 360, y: 810), options: [])
    context.restoreGState()

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for resolution in [1, 2] {
        let suffix = resolution == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try render(points * resolution).write(to: iconset.appendingPathComponent(name))
    }
}
try render(1024).write(to: destination.appendingPathComponent("AppIcon.png"))
try render(256).write(to: destination.appendingPathComponent("AppIcon-preview.png"))
print(iconset.path)
