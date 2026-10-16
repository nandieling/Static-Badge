import CWebP
import Foundation

/// 动态 WebP 编码器：逐帧追加，最后一次组装。
///
/// 内部缓冲是复用的，只能在创建它的那条线程上用完整个生命周期。
public final class WebPAnimEncoder {
    private var handle: UnsafeMutableRawPointer?

    /// - Parameter loopCount: 循环次数，0 表示无限循环。
    public init(width: Int, height: Int, bytesPerRow: Int, loopCount: Int = 0,
                quality: Double, lossless: Bool = false) throws {
        let created = SBWebPAnimEncoderNew(Int32(width), Int32(height), Int32(bytesPerRow),
                                          Int32(loopCount), 0, Float(quality),
                                          lossless ? 1 : 0)
        guard let created else {
            throw BadgeError.animationFailed(reason: "无法创建动图编码器")
        }
        handle = created
    }

    deinit {
        if let handle {
            SBWebPAnimEncoderDelete(handle)
        }
    }

    /// 追加一帧（画布来自 `BadgeCanvas`，行距按字节计）。
    public func addFrame(bytes: UnsafeRawPointer, bytesPerRow: Int,
                         durationMilliseconds: Int) throws {
        guard let handle else { throw BadgeError.animationFailed(reason: "编码器已释放") }
        let ok = SBWebPAnimEncoderAddFrame(handle, bytes.assumingMemoryBound(to: UInt8.self),
                                           Int32(bytesPerRow),
                                           Int32(max(1, durationMilliseconds)))
        guard ok != 0 else {
            throw BadgeError.animationFailed(reason: describeError(handle))
        }
    }

    /// 组装完整码流。
    public func finish() throws -> Data {
        guard let handle else { throw BadgeError.animationFailed(reason: "编码器已释放") }
        var buffer: UnsafeMutablePointer<UInt8>?
        defer {
            if let buffer {
                SBWebPFree(buffer)
            }
        }
        let written = SBWebPAnimEncoderFinish(handle, &buffer)
        guard written > 0, let buffer else {
            throw BadgeError.animationFailed(reason: describeError(handle))
        }
        self.handle = nil
        SBWebPAnimEncoderDelete(handle)
        return Data(bytes: buffer, count: written)
    }

    private func describeError(_ handle: UnsafeMutableRawPointer) -> String {
        guard let text = SBWebPAnimEncoderError(handle) else { return "未知错误" }
        let reason = String(cString: text)
        return reason.isEmpty ? "未知错误" : reason
    }
}

/// 解码出来的动态 WebP，主要给测试和自检用。
public struct WebPAnimation {
    public struct Frame {
        public let width: Int
        public let height: Int
        /// 内存顺序为 R,G,B,A，行距 = 宽 * 4。
        public let bytes: Data
        /// 这一帧显示结束的时间点（libwebp 的动图解码器按“结束时刻”报时间戳）。
        public let timestamp: TimeInterval
        public let duration: TimeInterval
    }

    public let width: Int
    public let height: Int
    /// 0 表示无限循环。
    public let loopCount: Int
    public let frameCount: Int
    public let frames: [Frame]
}

public extension WebP {
    static func decodeAnimation(_ data: Data) throws -> WebPAnimation {
        guard !data.isEmpty else { throw BadgeError.webpDecodeFailed(status: -1) }
        return try data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw BadgeError.webpDecodeFailed(status: -1)
            }
            // 解码器只持有数据的指针，因此整个取帧过程都要留在这段内存里。
            guard let decoder = SBWebPAnimDecoderNew(base, data.count) else {
                throw BadgeError.webpDecodeFailed(status: -2)
            }
            defer { SBWebPAnimDecoderDelete(decoder) }

            var info = SBWebPAnimationInfo()
            guard SBWebPAnimDecoderGetInfo(decoder, &info) != 0 else {
                throw BadgeError.webpDecodeFailed(status: -3)
            }

            let width = Int(info.width)
            let height = Int(info.height)
            let rowBytes = width * 4
            var pixels: [Data] = []
            var timestamps: [TimeInterval] = []
            var frame: UnsafePointer<UInt8>?
            var stride: Int32 = 0
            var timestamp: Int32 = 0
            while SBWebPAnimDecoderNext(decoder, &frame, &stride, &timestamp) != 0,
                  let frame {
                pixels.append(Data(bytes: frame, count: rowBytes * height))
                timestamps.append(Double(timestamp) / 1000)
            }
            guard !pixels.isEmpty else { throw BadgeError.webpDecodeFailed(status: -4) }

            var frames: [WebPAnimation.Frame] = []
            var previous = 0.0
            for index in pixels.indices {
                let stamp = timestamps[index]
                frames.append(WebPAnimation.Frame(
                    width: width, height: height, bytes: pixels[index],
                    timestamp: stamp,
                    duration: max(0, stamp - previous)))
                previous = stamp
            }
            return WebPAnimation(width: width, height: height,
                                 loopCount: Int(info.loop_count),
                                 frameCount: Int(info.frame_count), frames: frames)
        }
    }
}
