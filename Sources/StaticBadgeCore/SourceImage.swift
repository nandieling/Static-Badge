import CoreGraphics
import Foundation
import ImageIO

/// 已解码、并已按 EXIF 方向摆正的位图。
///
/// 所有坐标都用图像像素表示，原点在左上角，跟 Qt 版的场景坐标一致。
public struct SourceImage {
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public var pixelWidth: Int { cgImage.width }
    public var pixelHeight: Int { cgImage.height }
    public var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
    public var pixelRect: CGRect { CGRect(origin: .zero, size: pixelSize) }
}

public enum ImageLoader {
    /// 解码 ImageIO 支持的任意图片，并把 EXIF 方向烘进像素
    /// （等价于 Qt 版里的 `QImageReader.setAutoTransform(true)`）。
    public static func load(from url: URL) throws -> SourceImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BadgeError.unreadImage(reason: "文件不存在")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw BadgeError.unreadImage(reason: "格式不支持或文件已损坏")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let longestSide = max(width, height, 1)

        // 带方向的缩略图接口是把 EXIF 方向烘进像素的公开做法，
        // 长边上限取原图尺寸，因此不会真的降采样。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BadgeError.unreadImage(reason: "解码失败")
        }
        return SourceImage(cgImage: cgImage)
    }
}
