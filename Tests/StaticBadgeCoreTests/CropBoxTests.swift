import CoreGraphics
import XCTest
@testable import StaticBadgeCore

final class CropBoxTests: XCTestCase {
    private let landscape = CGSize(width: 200, height: 100)

    func test初始裁剪框是最大内切正方形并居中() {
        let box = CropBox.inscribed(in: landscape)
        XCTAssertEqual(box.side, 100)
        XCTAssertEqual(box.origin, CGPoint(x: 50, y: 0))
    }

    func test平移不会越出图像() {
        let box = CropBox.inscribed(in: landscape)
        XCTAssertEqual(box.moved(to: CGPoint(x: -500, y: -500), within: landscape).origin,
                       CGPoint(x: 0, y: 0))
        XCTAssertEqual(box.moved(to: CGPoint(x: 5_000, y: 5_000), within: landscape).origin,
                       CGPoint(x: 100, y: 0))
    }

    func test右下角拖动保持正方形并以对角为不动点() {
        let box = CropBox(origin: CGPoint(x: 50, y: 0), side: 100)
        let anchor = box.anchor(for: .bottomRight)
        XCTAssertEqual(anchor, CGPoint(x: 50, y: 0))

        // 横向拉得比纵向多，边长取两者较大值。
        let resized = CropBox.square(anchor: anchor, corner: .bottomRight,
                                     mouse: CGPoint(x: 130, y: 60), imageSize: landscape)
        XCTAssertNotNil(resized)
        XCTAssertEqual(resized!.side, 80, accuracy: 0.0001)
        XCTAssertEqual(resized!.origin.x, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(resized!.origin.y, anchor.y, accuracy: 0.0001)
    }

    func test缩放被图像边界夹住() {
        let box = CropBox(origin: CGPoint(x: 50, y: 0), side: 100)
        let anchor = box.anchor(for: .bottomRight)
        let resized = CropBox.square(anchor: anchor, corner: .bottomRight,
                                     mouse: CGPoint(x: 1_000, y: 1_000), imageSize: landscape)
        XCTAssertEqual(resized!.side, 100, accuracy: 0.0001)
    }

    func test缩放有最小边长() {
        let box = CropBox(origin: CGPoint(x: 50, y: 0), side: 100)
        let anchor = box.anchor(for: .bottomRight)
        let resized = CropBox.square(anchor: anchor, corner: .bottomRight,
                                     mouse: CGPoint(x: 51, y: 1), imageSize: landscape)
        XCTAssertEqual(resized!.side, CropBox.minimumSide, accuracy: 0.0001)
    }

    func test几乎没有余量时返回原状() {
        // 不动点离图像左上角只剩不到一像素，没有可缩放的空间。
        XCTAssertNil(CropBox.square(anchor: CGPoint(x: 0.5, y: 0.5), corner: .topLeft,
                                    mouse: .zero, imageSize: landscape))
    }

    func test左上角拖动移动的是左上角而对角固定() {
        let box = CropBox(origin: CGPoint(x: 50, y: 0), side: 100)
        let anchor = box.anchor(for: .topLeft)
        let resized = CropBox.square(anchor: anchor, corner: .topLeft,
                                     mouse: CGPoint(x: 110, y: 60), imageSize: landscape)
        XCTAssertEqual(resized!.side, 40, accuracy: 0.0001)
        XCTAssertEqual(resized!.origin, CGPoint(x: 110, y: 60))
        XCTAssertEqual(resized!.maxX, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(resized!.maxY, anchor.y, accuracy: 0.0001)
    }

    func test导出裁剪区会取整并夹在图像内() {
        let box = CropBox(origin: CGPoint(x: 49.6, y: -3.2), side: 100.4)
        let crop = box.integralCrop(imageSize: landscape)
        XCTAssertEqual(crop, IntegralCrop(x: 50, y: 0, side: 100))
    }
}
