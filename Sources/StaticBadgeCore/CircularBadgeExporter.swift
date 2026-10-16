import CoreGraphics
import Foundation

public struct ExportOptions {
    /// 0~100，对应该 Qt 版的 `QImage.save(path, "WEBP", 90)`。
    public var quality: Double
    public var lossless: Bool
    /// 导出正方形的边长；nil = 原始分辨率（即裁剪框边长）。
    public var outputSide: Int?
    /// 最终文件的字节上限；nil = 不限制。填了会自动往下找画质。
    public var maxBytes: Int?

    public init(quality: Double = 90, lossless: Bool = false,
                outputSide: Int? = nil, maxBytes: Int? = nil) {
        self.quality = quality
        self.lossless = lossless
        self.outputSide = outputSide
        self.maxBytes = maxBytes
    }

    public static let standard = ExportOptions()
}

/// 按裁剪框取正方形区域，圆内保留、圆外透明，输出 WebP。
public enum CircularBadgeExporter {
    public static func webPData(from source: SourceImage, crop: IntegralCrop,
                                options: ExportOptions = .standard) throws -> Data {
        let side = try BadgeCanvas.outputSide(for: crop, requested: options.outputSide)
        guard let context = BadgeCanvas.makeContext(side: side) else {
            throw BadgeError.contextUnavailable
        }
        try BadgeCanvas.draw(source.cgImage, crop: crop, in: context)
        // Quartz 的绘图是延迟落盘的，读缓冲前必须 flush。
        context.flush()

        guard let pointer = context.data else {
            throw BadgeError.contextUnavailable
        }
        let encode: (Int, (Double) -> Void) throws -> Data = { quality, _ in
            try WebP.encodeBGRA(bytes: pointer, width: side, height: side,
                                bytesPerRow: context.bytesPerRow,
                                quality: Double(quality), lossless: options.lossless)
        }
        guard let limit = options.maxBytes else {
            return try encode(Int(options.quality)) { _ in }
        }
        if options.lossless {
            // 无损编码没有画质旋钮，能不能塞进上限一次就见分晓。
            let data = try encode(100) { _ in }
            guard data.count <= limit else {
                throw BadgeError.sizeLimitExceeded(limit: limit, bestSize: data.count)
            }
            return data
        }
        return try QualitySearch.search(limitBytes: limit, encode: encode).data
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
