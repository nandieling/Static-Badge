/*
 * 把任意图片（png / webp / jpg / tiff / heic 等 ImageIO 支持的格式）切成
 * macOS 应用图标需要的 .iconset 目录。
 *
 *   swift tools/make-icns.swift 1.webp /tmp/AppIcon.iconset
 *   iconutil -c icns /tmp/AppIcon.iconset -o Sources/StaticBadge/Resources/AppIcon.icns
 */
import AppKit
import Foundation

let entries: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("用法: make-icns <源图片> <输出 .iconset 目录>\n".utf8))
    exit(1)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("无法读取图标源文件：\(sourceURL.path)\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for entry in entries {
    let pixels = entry.points * entry.scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .calibratedRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let data = render(image, into: bitmap, pixels: pixels) else {
        FileHandle.standardError.write(Data("生成 \(entry.name).png 失败\n".utf8))
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent("\(entry.name).png"))
}

/// 等比重绘到指定像素尺寸，保留透明通道。
func render(_ image: NSImage, into bitmap: NSBitmapImageRep, pixels: Int) -> Data? {
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

print("已生成 \(entries.count) 个尺寸：\(outputURL.path)")
