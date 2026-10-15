/*
 * 生成应用图标：深色圆角底板 + 绿色正方形裁剪框 + 蓝色内切圆 + 四角控制点，
 * 也就是软件画布上的那套视觉。
 *
 *   swift tools/make-icon.swift /tmp/AppIcon.iconset
 *   iconutil -c icns /tmp/AppIcon.iconset -o Sources/StaticBadge/Resources/AppIcon.icns
 */
import AppKit
import Foundation

func drawBadge(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let unit = size / 100
    let inset = 6 * unit
    let canvas = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)

    let background = NSBezierPath(roundedRect: canvas, xRadius: 22 * unit, yRadius: 22 * unit)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 36 / 255, green: 42 / 255, blue: 51 / 255, alpha: 1),
        NSColor(srgbRed: 15 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1),
    ])!
    gradient.draw(in: background, angle: -90)

    // 裁剪框：留出一圈，视觉上更像在框选一张图。
    let crop = canvas.insetBy(dx: 20 * unit, dy: 20 * unit)

    let photo = NSBezierPath(rect: crop)
    NSColor(srgbRed: 122 / 255, green: 148 / 255, blue: 176 / 255, alpha: 1).setFill()
    photo.fill()
    NSColor(srgbRed: 176 / 255, green: 198 / 255, blue: 219 / 255, alpha: 0.55).setFill()
    NSBezierPath(ovalIn: crop.insetBy(dx: 6 * unit, dy: 14 * unit)).fill()

    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(rect: NSRect(x: crop.minX, y: crop.minY,
                              width: crop.width, height: crop.height * 0.42)).fill()

    let square = NSBezierPath(rect: crop)
    square.lineWidth = 2.4 * unit
    NSColor(srgbRed: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1).setStroke()
    square.stroke()

    let circle = NSBezierPath(ovalIn: crop)
    circle.lineWidth = 2.4 * unit
    NSColor(srgbRed: 52 / 255, green: 152 / 255, blue: 219 / 255, alpha: 1).setStroke()
    circle.stroke()

    let handle = 7 * unit
    let handles = NSBezierPath()
    for corner in [crop.origin, NSPoint(x: crop.maxX, y: crop.minY),
                   NSPoint(x: crop.minX, y: crop.maxY), NSPoint(x: crop.maxX, y: crop.maxY)] {
        handles.appendRect(NSRect(x: corner.x - handle / 2, y: corner.y - handle / 2,
                                  width: handle, height: handle))
    }
    NSColor.white.setFill()
    handles.fill()
    NSColor(white: 0.08, alpha: 1).setStroke()
    handles.lineWidth = 0.8 * unit
    handles.stroke()

    return image
}

func pngData(_ image: NSImage, pixelSize: Int) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法: make-icon <输出 .iconset 目录>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let entries: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]
for entry in entries {
    let data = try write(drawBadge(size: CGFloat(entry.points)), pixelSize: entry.points * entry.scale,
                         name: entry.name, directory: output)
    print("写入 \(entry.name).png (\(entry.points * entry.scale)px, \(data.count) bytes)")
}

func write(_ image: NSImage, pixelSize: Int, name: String, directory: URL) throws -> Data {
    guard let data = pngData(image, pixelSize: pixelSize) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败: \(name)"])
    }
    try data.write(to: directory.appendingPathComponent("\(name).png"))
    return data
}
