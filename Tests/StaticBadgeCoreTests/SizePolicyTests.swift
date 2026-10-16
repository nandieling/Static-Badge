import AVFoundation
import CoreGraphics
import XCTest
@testable import StaticBadgeCore

/// 输出尺寸与“文件不超过多大”这两条规则的行为。
final class SizePolicyTests: XCTestCase {
    private var movies: [URL] = []

    override func tearDown() {
        for url in movies {
            try? FileManager.default.removeItem(at: url)
        }
        movies.removeAll()
        super.tearDown()
    }

    /// 160x160 的逐像素噪点：细节多到有损编码压不动，适合拿来试体积上限。
    private var mosaic: SourceImage {
        let palette: [TestSupport.Pixel] = [.red, .green, .blue]
        return SourceImage(cgImage: TestSupport.image(width: 160, height: 160) { x, y in
            let hash = (x &* 73_856_093) ^ (y &* 19_349_663)
            return palette[abs(hash) % palette.count]
        })
    }

    private var crop: IntegralCrop { IntegralCrop(x: 0, y: 0, side: 160) }

    // MARK - 输出尺寸

    func test输出尺寸可以缩放到指定边长() throws {
        let export = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(outputSide: 64))))
        XCTAssertEqual(export.width, 64)
        XCTAssertEqual(export.height, 64)
        // 圆外还是透明，圆内还是不透明。
        XCTAssertEqual(TestSupport.pixel(export, x: 0, y: 0).a, 0)
        XCTAssertEqual(TestSupport.pixel(export, x: 63, y: 63).a, 0)
        XCTAssertGreaterThan(TestSupport.pixel(export, x: 32, y: 32).a, 250)
    }

    func test放大输出不会翻转画面() throws {
        let source = SourceImage(cgImage: TestSupport.image(width: 21, height: 21) { _, y in
            y < 11 ? TestSupport.Pixel.red : TestSupport.Pixel.blue
        })
        let export = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: source, crop: IntegralCrop(x: 0, y: 0, side: 21),
            options: ExportOptions(outputSide: 84))))
        XCTAssertEqual(TestSupport.pixel(export, x: 42, y: 10).r, 220, accuracy: 25, "上半应当还是红")
        XCTAssertEqual(TestSupport.pixel(export, x: 42, y: 74).b, 220, accuracy: 25, "下半应当还是蓝")
    }

    func test输出尺寸小于1会报错() {
        XCTAssertThrowsError(try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(outputSide: 0))) { error in
            XCTAssertEqual(error as? BadgeError, .invalidOutputSize)
        }
    }

    // MARK - 体积上限

    func test上限宽松时保留最高画质() throws {
        let roomy = try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop,
            options: ExportOptions(outputSide: 96, maxBytes: 8_000_000))
        let best = try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(quality: 100, outputSide: 96))
        XCTAssertEqual(roomy, best, "画质 100 就已经塞得进上限，不该再往下压")
    }

    func test上限会压低画质但不越过上限() throws {
        let full = try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(quality: 100))
        // 画质 1 的体积是这件事的“物理下限”，上限取它的两倍，保证一定塞得进。
        let floor = try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(quality: 1))
        XCTAssertLessThan(floor.count, full.count / 4, "这张图应当有明显的画质压缩空间")
        let limit = max(floor.count * 2, 1024)
        let limited = try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop,
            options: ExportOptions(maxBytes: limit))
        XCTAssertLessThanOrEqual(limited.count, limit)
        XCTAssertGreaterThan(limited.count, floor.count / 2, "画质不该被压到看不见")
        XCTAssertLessThan(limited.count, full.count, "既然限制了体积就不该还交最高画质")
        let decoded = try XCTUnwrap(TestSupport.pixels(limited))
        XCTAssertEqual(decoded.width, 160)
        XCTAssertEqual(TestSupport.pixel(decoded, x: 0, y: 0).a, 0)
    }

    func test上限小到不可能时给出实测体积() throws {
        XCTAssertThrowsError(try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop, options: ExportOptions(maxBytes: 400))) { error in
            guard let badge = error as? BadgeError,
                  case BadgeError.sizeLimitExceeded(let limit, let bestSize) = badge else {
                return XCTFail("应当报体积上限不够，实际是 \(error)")
            }
            XCTAssertEqual(limit, 400)
            XCTAssertGreaterThan(bestSize, limit)
        }
    }

    func test无损编码超上限时直接报错() throws {
        XCTAssertThrowsError(try CircularBadgeExporter.webPData(
            from: mosaic, crop: crop,
            options: ExportOptions(lossless: true, maxBytes: 1_024))) { error in
            guard let badge = error as? BadgeError,
                  case BadgeError.sizeLimitExceeded = badge else {
                return XCTFail("应当报体积上限不够，实际是 \(error)")
            }
        }
    }

    // MARK - 动图

    func test动图可以指定输出尺寸() throws {
        let url = try VideoFixture.makeMovie(seconds: 1, fps: 24)
        movies.append(url)
        let source = try VideoBadgeSource(url: url)
        let result = try AnimatedBadgeExporter.webPData(
            source: source, crop: IntegralCrop(x: 0, y: 0, side: 128), start: 0, duration: 1,
            options: AnimatedExportOptions(fps: 24, outputSide: 64))
        XCTAssertEqual(result.side, 64)
        let animation = try WebP.decodeAnimation(result.data)
        XCTAssertEqual(animation.width, 64)
        XCTAssertEqual(animation.height, 64)
        XCTAssertEqual(animation.loopCount, 0)
        for frame in animation.frames {
            XCTAssertEqual(frame.width, 64)
            XCTAssertEqual(frame.height, 64)
        }
    }

    func test动图体积上限会压低画质() throws {
        let url = try VideoFixture.makeMovie(seconds: 1, fps: 24)
        movies.append(url)
        let source = try VideoBadgeSource(url: url)
        let crop = IntegralCrop(x: 0, y: 0, side: 128)
        let free = try AnimatedBadgeExporter.webPData(
            source: source, crop: crop, start: 0, duration: 1,
            options: AnimatedExportOptions(fps: 24))
        let floor = try AnimatedBadgeExporter.webPData(
            source: source, crop: crop, start: 0, duration: 1,
            options: AnimatedExportOptions(fps: 24, quality: 1))
        XCTAssertLessThan(floor.data.count, free.data.count / 2, "这段素材应当有明显的画质压缩空间")
        let limit = max(floor.data.count * 2, 1024)
        let limited = try AnimatedBadgeExporter.webPData(
            source: source, crop: crop, start: 0, duration: 1,
            options: AnimatedExportOptions(fps: 24, maxBytes: limit))
        XCTAssertLessThanOrEqual(limited.data.count, limit)
        XCTAssertGreaterThan(limited.attempts, 1, "限制体积至少要重编过一次")
        XCTAssertLessThan(limited.quality, free.quality)
        XCTAssertLessThanOrEqual(limited.attempts, 5, "重编次数要被框住")
        XCTAssertEqual(limited.frameCount, free.frameCount, "帧数不该因为压缩而变化")

        let animation = try WebP.decodeAnimation(limited.data)
        XCTAssertGreaterThan(animation.frameCount, 0)
        XCTAssertLessThanOrEqual(animation.frameCount, limited.frameCount)
        let corner = VideoFixture.RGBA(width: animation.width, height: animation.height,
                                       bytes: [UInt8](animation.frames[0].bytes))
        XCTAssertLessThanOrEqual(corner.pixel(0, 0).a, 8, "圆外还得是透明的")
    }

    func test估算帧数跟着帧率走() {
        XCTAssertEqual(AnimatedBadgeExporter.estimatedFrameCount(duration: 3, fps: 60), 180)
        XCTAssertEqual(AnimatedBadgeExporter.estimatedFrameCount(duration: 3, fps: 15), 45)
    }
}
