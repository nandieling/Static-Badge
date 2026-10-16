import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

/// 视频源。所有坐标都用“摆正后的画面像素”，原点在左上角，跟静态图片那套一致。
///
/// - 预览帧走 `AVAssetImageGenerator`（它会自己应用 preferredTransform）。
/// - 导出帧走 `AVAssetReader` 顺序解码，再由 `BadgeCanvas` 手动套用同一个
///   preferredTransform，两条路径落在同一个坐标空间里。
public final class VideoBadgeSource {
    public let url: URL
    /// 摆正后的画面尺寸，裁剪框就在这个空间里。
    public let pixelSize: CGSize
    public let duration: TimeInterval
    /// 打开时解出的一帧，界面可以立刻显示，不必等用户拖时间轴。
    public let firstFrame: CGImage

    fileprivate let asset: AVURLAsset
    fileprivate let videoTrack: AVAssetTrack
    fileprivate let preferredTransform: CGAffineTransform
    fileprivate let naturalSize: CGSize
    private let generator: AVAssetImageGenerator

    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BadgeError.unreadVideo(reason: "文件不存在")
        }

        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw BadgeError.videoHasNoVideoTrack
        }
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else {
            throw BadgeError.unreadVideo(reason: "读不到时长")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = .zero
        // 首帧只要求“接近 0 秒”，容差放开会快很多。
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .zero
        let firstTime = CMTime(seconds: min(0.05, seconds / 2), preferredTimescale: 600)
        guard let frame = try? generator.copyCGImage(at: firstTime, actualTime: nil) else {
            throw BadgeError.unreadVideo(reason: "解不出画面")
        }

        self.url = url
        self.asset = asset
        self.videoTrack = track
        self.generator = generator
        self.duration = seconds
        self.firstFrame = frame
        self.naturalSize = track.naturalSize
        self.preferredTransform = track.preferredTransform
        self.pixelSize = CGSize(width: frame.width, height: frame.height)
    }

    /// 精确取某一时刻的画面，给时间轴预览用。
    public func previewImage(at seconds: TimeInterval) throws -> SourceImage {
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: clamped(seconds), preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
            throw BadgeError.unreadVideo(reason: "解不出这一帧")
        }
        return SourceImage(cgImage: image)
    }

    public func clamped(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, 0), max(0, duration))
    }

    /// 把显示空间（左上原点）的裁剪框换算成整幅画面的整数边界。
    fileprivate var displayCropBounds: CGRect {
        CGRect(x: 0, y: 0, width: pixelSize.width.rounded(), height: pixelSize.height.rounded())
    }

    /// 建立顺序读取器，读取当前裁剪区需要的帧。
    public func makeFrameStream(start: TimeInterval, duration: TimeInterval, fps: Double,
                                crop: IntegralCrop, outputSide: Int? = nil) throws
        -> VideoFrameStream {
        guard fps > 0, duration > 0 else { throw BadgeError.videoRangeEmpty }
        let bounds = displayCropBounds
        guard crop.side >= 1, crop.x >= 0, crop.y >= 0,
              crop.x + crop.side <= Int(bounds.width),
              crop.y + crop.side <= Int(bounds.height) else {
            throw BadgeError.invalidCrop
        }
        let side = try BadgeCanvas.outputSide(for: crop, requested: outputSide)
        let from = clamped(start)
        let to = clamped(start + duration)
        guard to > from else { throw BadgeError.videoRangeEmpty }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                       end: CMTime(seconds: to, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard reader.canAdd(output) else {
            throw BadgeError.unreadVideo(reason: "这个视频的格式不支持逐帧读取")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw BadgeError.unreadVideo(
                reason: reader.error?.localizedDescription ?? "读取失败")
        }
        return VideoFrameStream(reader: reader, output: output, startTime: from,
                                naturalSize: naturalSize, transform: preferredTransform,
                                crop: crop, fps: fps, canvasSide: side)
    }
}

/// `AVAssetReader` 的按时间取样游标：每 `1/fps` 秒取一帧，画进导出画布并挖好圆。
///
/// 画布只建一次，逐帧复用；`advance()` 成功后调用方就可以读 `context.data`。
public final class VideoFrameStream {
    public let context: CGContext

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let naturalSize: CGSize
    private let transform: CGAffineTransform
    private let crop: IntegralCrop
    private let frameInterval: TimeInterval
    private let startTime: TimeInterval

    /// 最近一帧在视频里的时间点（秒）。
    public private(set) var presentationTime: TimeInterval = 0
    public private(set) var frameCount = 0

    fileprivate init(reader: AVAssetReader, output: AVAssetReaderTrackOutput,
                     startTime: TimeInterval, naturalSize: CGSize,
                     transform: CGAffineTransform, crop: IntegralCrop, fps: Double,
                     canvasSide: Int) {
        self.reader = reader
        self.output = output
        self.startTime = startTime
        self.naturalSize = naturalSize
        self.transform = transform
        self.crop = crop
        self.frameInterval = 1 / fps
        self.context = BadgeCanvas.makeContext(side: canvasSide)!
    }

    /// 读取并绘制下一帧。返回 false 表示这一段已经读完。
    public func advance() throws -> Bool {
        let target = startTime + Double(frameCount) * frameInterval
        // 取样接口在 AVAssetReaderOutput 上，reader 只负责状态与时间范围。
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            guard seconds.isFinite else { continue }
            // 允许半帧的误差，避免可变帧率视频卡在同一目标上。
            if seconds + frameInterval * 0.5 >= target {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                    throw BadgeError.unreadVideo(reason: "样本里没有画面")
                }
                try draw(buffer)
                presentationTime = seconds
                frameCount += 1
                return true
            }
        }
        return false
    }

    private func draw(_ buffer: CVImageBuffer) throws {
        guard reader.error == nil || reader.status == .completed else {
            throw BadgeError.unreadVideo(
                reason: reader.error?.localizedDescription ?? "读取失败")
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        // 用 VideoToolbox 生成 CGImage，它会带上像素缓冲自带的色彩信息，
        // 直接自己包缓冲会把 709/601 当成 sRGB，颜色偏艳。
        var created: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &created) == noErr,
              let image = created else {
            throw BadgeError.unreadVideo(reason: "画面转换失败")
        }
        try BadgeCanvas.drawVideoFrame(image, transform: transform, naturalSize: naturalSize,
                                       crop: crop, in: context)
    }
}
