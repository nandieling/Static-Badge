import CoreGraphics
import Foundation

public struct AnimatedExportOptions {
    /// 每秒取多少帧。
    public var fps: Double
    /// 0~100。设了 `maxBytes` 时只当作起点参考，实际画质由体积上限反推。
    public var quality: Double
    /// 0 = 无限循环。
    public var loopCount: Int
    public var lossless: Bool
    /// 导出正方形的边长；nil = 原始分辨率（即裁剪框边长）。
    public var outputSide: Int?
    /// 最终文件的字节上限；nil = 不限制。填了会整段重编几次来逼近上限。
    public var maxBytes: Int?

    public init(fps: Double = 12, quality: Double = 90, loopCount: Int = 0,
                lossless: Bool = false, outputSide: Int? = nil, maxBytes: Int? = nil) {
        self.fps = fps
        self.quality = quality
        self.loopCount = loopCount
        self.lossless = lossless
        self.outputSide = outputSide
        self.maxBytes = maxBytes
    }

    public static let standard = AnimatedExportOptions()
}

/// 视频 → 圆形透明背景的动态 WebP。
///
/// 每一帧都用 `BadgeCanvas` 走一遍“裁正方形 + 挖内切圆”，和静态图片那条路径完全一致。
public enum AnimatedBadgeExporter {
    public struct Result {
        public let data: Data
        public let frameCount: Int
        public let duration: TimeInterval
        /// 实际导出的边长。
        public let side: Int
        /// 最终用的画质。
        public let quality: Int
        /// 整段重编了几次（不限制体积时恒为 1）。
        public let attempts: Int
    }

    public static func estimatedFrameCount(duration: TimeInterval, fps: Double) -> Int {
        guard duration > 0, fps > 0 else { return 0 }
        return max(1, Int((duration * fps).rounded(.up)))
    }

    /// 导出动态 WebP。
    ///
    /// - Parameters:
    ///   - start: 从视频的哪一秒开始（秒）。
    ///   - duration: 导出多长（秒），留空表示到视频结尾。
    ///   - progress: 进度回调，0~1。限制体积时会跨多次压缩算总进度。
    ///   - isCancelled: 返回 true 时中断，抛 `BadgeError.cancelled`。
    public static func webPData(source: VideoBadgeSource, crop: IntegralCrop,
                                start: TimeInterval, duration: TimeInterval,
                                options: AnimatedExportOptions = .standard,
                                progress: ((Double) -> Void)? = nil,
                                isCancelled: (() -> Bool)? = nil) throws -> Result {
        let side = try BadgeCanvas.outputSide(for: crop, requested: options.outputSide)
        // 限制体积时每帧都要重编一遍，记下最后一次的信息用于回填结果。
        let passInfo = Box<(frames: Int, duration: TimeInterval)>((frames: 0, duration: 0))

        /// 把整段视频重跑一遍：解码 → 画圆 → 编码。限制体积时会被调好几次。
        func compress(quality: Double, report: (Double) -> Void) throws -> Data {
            let stream = try source.makeFrameStream(start: start, duration: duration,
                                                    fps: options.fps, crop: crop,
                                                    outputSide: side)
            let estimated = Double(max(1, estimatedFrameCount(duration: duration,
                                                              fps: options.fps)))
            let encoder = try WebPAnimEncoder(width: side, height: side,
                                             bytesPerRow: side * 4,
                                             loopCount: options.loopCount,
                                             quality: quality,
                                             lossless: options.lossless)

            var encoded = 0
            var covered = 0.0
            while true {
                if isCancelled?() == true {
                    throw BadgeError.cancelled
                }
                guard try stream.advance() else { break }

                // 帧时长用“累计时间点相减”算，避免每帧取整误差不停累加。
                let secondsPerFrame = 1 / options.fps
                let before = Double(encoded) * secondsPerFrame
                let after = before + secondsPerFrame
                let durationMs = Int((after * 1000).rounded(.down)) - Int((before * 1000).rounded(.down))

                // Quartz 的绘图是延迟落盘的，读缓冲前必须 flush。
                stream.context.flush()
                guard let pointer = stream.context.data else {
                    throw BadgeError.contextUnavailable
                }
                try encoder.addFrame(bytes: pointer, bytesPerRow: stream.context.bytesPerRow,
                                     durationMilliseconds: max(1, durationMs))
                encoded += 1
                covered = after
                report(min(1, Double(encoded) / estimated))
            }

            guard encoded > 0 else { throw BadgeError.videoRangeEmpty }
            passInfo.set((encoded, covered))
            return try encoder.finish()
        }

        func outcome(_ data: Data, _ quality: Int, _ attempts: Int) -> Result {
            let info = passInfo.get()
            return Result(data: data, frameCount: info.frames, duration: info.duration,
                          side: side, quality: quality, attempts: attempts)
        }

        guard let limit = options.maxBytes else {
            let data = try compress(quality: options.quality) { progress?($0) }
            return outcome(data, Int(options.quality.rounded()), 1)
        }
        if options.lossless {
            // 无损编码没有画质旋钮，能不能塞进上限一次就见分晓。
            let data = try compress(quality: 100) { progress?($0) }
            guard data.count <= limit else {
                throw BadgeError.sizeLimitExceeded(limit: limit, bestSize: data.count)
            }
            return outcome(data, 100, 1)
        }
        let search = try QualitySearch.search(limitBytes: limit, encode: { quality, report in
            try compress(quality: Double(quality), report: report)
        }, progress: { progress?($0) })
        return outcome(search.data, search.quality, search.attempts)
    }
}
