import CWebP
import Foundation

/// libwebp 的 Swift 封装。macOS 的 ImageIO 不能写 WebP，所以导出走这里。
public enum WebP {
    /// 内嵌 libwebp 的版本号，用于“关于”面板和日志。
    public static var libraryVersion: String { String(cString: SBWebPVersionString()) }

    /// 编码内存顺序为 B,G,R,A 的位图（CGBitmapContext 的小端 premultipliedFirst 布局）。
    public static func encodeBGRA(bytes: UnsafeRawPointer, width: Int, height: Int,
                                  bytesPerRow: Int, quality: Double,
                                  lossless: Bool) throws -> Data {
        var buffer: UnsafeMutablePointer<UInt8>?
        defer {
            if let buffer = buffer {
                SBWebPFree(buffer)
            }
        }
        let written = SBWebPEncodeBGRA(bytes.assumingMemoryBound(to: UInt8.self),
                                      Int32(width), Int32(height), Int32(bytesPerRow),
                                      Float(quality), lossless ? 1 : 0, &buffer)
        guard written > 0, let buffer = buffer else {
            throw BadgeError.encodingFailed
        }
        return Data(bytes: buffer, count: written)
    }

    public struct DecodedImage {
        public let width: Int
        public let height: Int
        /// 内存顺序为 R,G,B,A，按行从上往下。
        public let bytes: Data
    }

    /// 解码 WebP，主要给测试和自检用。
    public static func decodeRGBA(_ data: Data) throws -> DecodedImage {
        guard !data.isEmpty else {
            throw BadgeError.webpDecodeFailed(status: -1)
        }
        var width: Int32 = 0
        var height: Int32 = 0
        var buffer: UnsafeMutablePointer<UInt8>?
        defer {
            if let buffer = buffer {
                SBWebPFree(buffer)
            }
        }
        let status = data.withUnsafeBytes { raw -> Int in
            Int(SBWebPDecodeRGBA(raw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                 &width, &height, &buffer))
        }
        guard status == 0, let buffer = buffer, width > 0, height > 0 else {
            throw BadgeError.webpDecodeFailed(status: status)
        }
        return DecodedImage(width: Int(width), height: Int(height),
                            bytes: Data(bytes: buffer, count: Int(width) * Int(height) * 4))
    }
}
