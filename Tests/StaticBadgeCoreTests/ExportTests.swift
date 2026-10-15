import CoreGraphics
import XCTest
@testable import StaticBadgeCore

final class ExportTests: XCTestCase {
    /// 21x21，上半红下半蓝，用于确认导出结果没有上下颠倒。
    private var halfSplit: SourceImage {
        SourceImage(cgImage: TestSupport.image(width: 21, height: 21) { _, y in
            y < 11 ? TestSupport.Pixel.red : TestSupport.Pixel.blue
        })
    }

    /// 21x21，左半红右半蓝，用于确认导出结果没有左右翻转。
    private var verticalSplit: SourceImage {
        SourceImage(cgImage: TestSupport.image(width: 21, height: 21) { x, _ in
            x < 11 ? TestSupport.Pixel.red : TestSupport.Pixel.blue
        })
    }

    func test导出尺寸等于裁剪边长() throws {
        let export = try CircularBadgeExporter.webPData(
            from: halfSplit, crop: IntegralCrop(x: 0, y: 0, side: 21))
        let decoded = try XCTUnwrap(TestSupport.pixels(export))
        XCTAssertEqual(decoded.width, 21)
        XCTAssertEqual(decoded.height, 21)
    }

    func test圆外透明圆内不透明() throws {
        let export = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: halfSplit, crop: IntegralCrop(x: 0, y: 0, side: 21))))
        // 四角在外接圆之外。
        for corner in [(0, 0), (20, 0), (0, 20), (20, 20)] {
            XCTAssertEqual(TestSupport.pixel(export, x: corner.0, y: corner.1).a, 0,
                           "角 \(corner) 应当完全透明")
        }
        // 中心在内切圆之内，alpha 无损保留。
        XCTAssertEqual(TestSupport.pixel(export, x: 10, y: 10).a, 255)
    }

    func test圆形边缘是抗锯齿过渡() throws {
        let export = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: halfSplit, crop: IntegralCrop(x: 0, y: 0, side: 21))))
        // 沿中心行从左往右进入圆内，必须出现中间灰度而不是 0 直接跳到 255。
        let row = (0..<5).map { TestSupport.pixel(export, x: $0, y: 10).a }
        XCTAssertTrue(row.contains { $0 > 0 && $0 < 255 }, "边缘 alpha 序列：\(row)")
    }

    func test导出内容方向与原图一致() throws {
        let crop = IntegralCrop(x: 0, y: 0, side: 21)
        let topBottom = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: halfSplit, crop: crop)))
        // (10,1) 靠近顶边，(10,19) 靠近底边，都在圆内。
        let top = TestSupport.pixel(topBottom, x: 10, y: 1)
        let bottom = TestSupport.pixel(topBottom, x: 10, y: 19)
        XCTAssertGreaterThan(top.r, top.b, "上半应仍是红色")
        XCTAssertGreaterThan(bottom.b, bottom.r, "下半应仍是蓝色")

        let leftRight = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: verticalSplit, crop: crop)))
        let left = TestSupport.pixel(leftRight, x: 1, y: 10)
        let right = TestSupport.pixel(leftRight, x: 19, y: 10)
        XCTAssertGreaterThan(left.r, left.b, "左半应仍是红色")
        XCTAssertGreaterThan(right.b, right.r, "右半应仍是蓝色")
    }

    func test只裁切指定区域() throws {
        // 40x40，右上 20x20 为绿色，裁右上角。
        let source = SourceImage(cgImage: TestSupport.image(width: 40, height: 40) { x, y in
            (x >= 20 && y < 20) ? TestSupport.Pixel.green : TestSupport.Pixel.blue
        })
        let export = try XCTUnwrap(TestSupport.pixels(try CircularBadgeExporter.webPData(
            from: source, crop: IntegralCrop(x: 10, y: 5, side: 20))))
        XCTAssertEqual(export.width, 20)
        // 裁剪区内 y=6 已经越过原图 y=25，应该变蓝。
        let below = TestSupport.pixel(export, x: 10, y: 16)
        XCTAssertGreaterThan(below.b, below.g)
    }

    func test裁剪区越界时报错() {
        XCTAssertThrowsError(try CircularBadgeExporter.webPData(
            from: halfSplit, crop: IntegralCrop(x: 5, y: 5, side: 20))) { error in
            XCTAssertEqual(error as? BadgeError, .invalidCrop)
        }
    }

    func test文件名冲突时依次追加序号() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("StaticBadgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func touch(_ name: String) throws {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path,
                                           contents: Data([0]))
        }

        XCTAssertEqual(CircularBadgeExporter.uniqueFileURL(in: directory, baseName: "badge").lastPathComponent,
                       "badge.webp")
        try touch("badge.webp")
        XCTAssertEqual(CircularBadgeExporter.uniqueFileURL(in: directory, baseName: "badge").lastPathComponent,
                       "badge_1.webp")
        try touch("badge_1.webp")
        XCTAssertEqual(CircularBadgeExporter.uniqueFileURL(in: directory, baseName: "badge").lastPathComponent,
                       "badge_2.webp")
    }
}
