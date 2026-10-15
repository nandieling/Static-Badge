import CoreGraphics
import Foundation
import StaticBadgeCore
import XCTest

/// 测试用的小工具：从 RGBA 字节构造 CGImage，以及读回导出结果里的像素。
enum TestSupport {
    struct Pixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8

        static let red = Pixel(red: 220, green: 20, blue: 20, alpha: 255)
        static let green = Pixel(red: 20, green: 200, blue: 20, alpha: 255)
        static let blue = Pixel(red: 20, green: 20, blue: 220, alpha: 255)
    }

    /// `paint` 决定该像素的颜色，坐标原点在左上角。
    static func image(width: Int, height: Int, paint: (_ x: Int, _ y: Int) -> Pixel) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let buffer = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = paint(x, y)
                let offset = (y * width + x) * 4
                buffer[offset] = pixel.red
                buffer[offset + 1] = pixel.green
                buffer[offset + 2] = pixel.blue
                buffer[offset + 3] = pixel.alpha
            }
        }
        return context.makeImage()!
    }

    static func pixels(_ export: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
        do {
            let decoded = try WebP.decodeRGBA(export)
            return (decoded.width, decoded.height, [UInt8](decoded.bytes))
        } catch {
            XCTFail("导出结果无法解码：\(error.localizedDescription)（\(export.count) 字节）")
            return nil
        }
    }

    static func pixel(_ decoded: (width: Int, height: Int, bytes: [UInt8]), x: Int, y: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = (y * decoded.width + x) * 4
        return (decoded.bytes[offset], decoded.bytes[offset + 1],
                decoded.bytes[offset + 2], decoded.bytes[offset + 3])
    }
}
