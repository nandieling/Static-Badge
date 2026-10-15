import CoreGraphics
import Foundation

public struct ExportOptions {
    /// 0~100，对应该 Qt 版的 `QImage.save(path, "WEBP", 90)`。
    public var quality: Double
    public var lossless: Bool

    public init(quality: Double = 90, lossless: Bool = false) {
        self.quality = quality
        self.lossless = lossless
    }

    public static let standard = ExportOptions()
}

/// 按裁剪框取正方形区域，圆内保留、圆外透明，输出 WebP。
public enum CircularBadgeExporter {
    public static func webPData(from source: SourceImage, crop: IntegralCrop,
                                options: ExportOptions = .standard) throws -> Data {
        let image = source.cgImage
        guard crop.side >= 1, crop.x >= 0, crop.y >= 0,
              crop.x + crop.side <= image.width,
              crop.y + crop.side <= image.height else {
            throw BadgeError.invalidCrop
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: crop.side, height: crop.side,
                                      bitsPerComponent: 8, bytesPerRow: crop.side * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw BadgeError.contextUnavailable
        }

        let canvas = CGRect(x: 0, y: 0, width: CGFloat(crop.side), height: CGFloat(crop.side))
        context.clear(canvas)
        context.interpolationQuality = .none
        guard let cropped = image.cropping(to: crop.rect) else {
            throw BadgeError.invalidCrop
        }
        // CGBitmapContext 的缓冲首行对应画面顶行，与 libwebp 的行序一致，无需翻转。
        context.draw(cropped, in: canvas)

        // 挖掉内切圆以外的区域。Core Graphics 的 destinationIn 不会清除路径外的像素，
        // 这里用奇偶填充的“整幅矩形减去内切圆”圆环配 destinationOut，
        // 得到真正的半透明抗锯齿边缘。
        context.setBlendMode(.destinationOut)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let ring = CGMutablePath()
        ring.addRect(canvas)
        ring.addEllipse(in: canvas)
        context.addPath(ring)
        context.fillPath(using: .evenOdd)

        // Quartz 的绘图是延迟落盘的，读缓冲前必须 flush。
        context.flush()

        guard let pointer = context.data else {
            throw BadgeError.contextUnavailable
        }
        return try WebP.encodeBGRA(bytes: pointer, width: crop.side, height: crop.side,
                                   bytesPerRow: context.bytesPerRow,
                                   quality: options.quality, lossless: options.lossless)
    }

    /// `原名.webp`，若已存在则依次尝试 `_1`、`_2`……
    public static func uniqueFileURL(in directory: URL, baseName: String,
                                     fileManager: FileManager = .default) -> URL {
        let base = directory.appendingPathComponent(baseName)
        let first = base.appendingPathExtension("webp")
        guard fileManager.fileExists(atPath: first.path) else { return first }
        var index = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)_\(index)")
                .appendingPathExtension("webp")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
