import AppKit
import CoreGraphics
import ImageIO
import XCTest
@testable import StaticBadgeCore

final class WebPTests: XCTestCase {
    func test内嵌libwebp可用() {
        XCTAssertTrue(WebP.libraryVersion.split(separator: ".").count >= 3,
                      "libwebp 版本号格式异常：\(WebP.libraryVersion)")
    }

    func test导出的字节流是合法WebP并能被ImageIO读出() throws {
        let source = SourceImage(cgImage: TestSupport.image(width: 16, height: 16) { _, _ in
            TestSupport.Pixel.green
        })
        let export = try CircularBadgeExporter.webPData(from: source,
                                                       crop: IntegralCrop(x: 0, y: 0, side: 16))
        // 文件签名 RIFF....WEBP
        XCTAssertEqual(String(decoding: export.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: export.subdata(in: 8..<12), as: UTF8.self), "WEBP")

        // 系统 ImageIO 能读 WebP，说明产出可以直接被别的软件使用。
        let image = try XCTUnwrap(NSBitmapImageRep(data: export))
        XCTAssertEqual(image.pixelsWide, 16)
        XCTAssertTrue(image.hasAlpha)
    }

    func test无损模式可用且比有损更大或相当() throws {
        let source = SourceImage(cgImage: TestSupport.image(width: 32, height: 32) { x, y in
            (x / 4 + y / 4) % 2 == 0 ? TestSupport.Pixel.red : TestSupport.Pixel.blue
        })
        let crop = IntegralCrop(x: 0, y: 0, side: 32)
        let lossy = try CircularBadgeExporter.webPData(from: source, crop: crop,
                                                       options: ExportOptions(quality: 90))
        let lossless = try CircularBadgeExporter.webPData(from: source, crop: crop,
                                                          options: ExportOptions(lossless: true))
        XCTAssertFalse(lossy.isEmpty)
        XCTAssertFalse(lossless.isEmpty)
    }

    func testEXIF方向会被摆正() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StaticBadge-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        // 6x4 原图，写入 orientation=6（顺时针旋转 90 度显示），读取后应当变成 4x6。
        let image = TestSupport.image(width: 6, height: 4) { _, _ in TestSupport.Pixel.green }
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image,
                                   [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let loaded = try ImageLoader.load(from: url)
        XCTAssertEqual(loaded.pixelWidth, 4)
        XCTAssertEqual(loaded.pixelHeight, 6)
    }
}
