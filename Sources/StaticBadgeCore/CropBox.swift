import CoreGraphics
import Foundation

/// 正方形裁剪框的四角，对应 Qt 版里的 "tl" / "tr" / "bl" / "br"。
public enum CropCorner: Int, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// 正方形裁剪框。坐标是图像像素，原点在左上角。
///
/// 平移和缩放的规则逐条对应 Qt 版的 `_move_to` / `_resize_to`。
public struct CropBox: Equatable {
    /// 缩放下限（图像像素），与 Qt 版的 `_min_side` 相同。
    public static let minimumSide: CGFloat = 40
    /// 角上控制点边长，Qt 版是场景坐标 12，这里用视图坐标 12。
    public static let handleSize: CGFloat = 12

    /// 左上角位置（图像坐标）。
    public var origin: CGPoint
    public var side: CGFloat

    public init(origin: CGPoint, side: CGFloat) {
        self.origin = origin
        self.side = side
    }

    public var size: CGSize { CGSize(width: side, height: side) }
    public var rect: CGRect { CGRect(origin: origin, size: size) }
    public var minX: CGFloat { origin.x }
    public var minY: CGFloat { origin.y }
    public var maxX: CGFloat { origin.x + side }
    public var maxY: CGFloat { origin.y + side }

    /// 初始裁剪框：图像的最大内切正方形并居中。
    public static func inscribed(in imageSize: CGSize) -> CropBox {
        let side = min(imageSize.width, imageSize.height)
        return CropBox(origin: CGPoint(x: (imageSize.width - side) / 2,
                                      y: (imageSize.height - side) / 2),
                       side: side)
    }

    /// 平移到指定位置，边长不变，并夹在图像内。
    public func moved(to desiredOrigin: CGPoint, within imageSize: CGSize) -> CropBox {
        let limitX = max(0, imageSize.width - side)
        let limitY = max(0, imageSize.height - side)
        return CropBox(origin: CGPoint(x: min(max(desiredOrigin.x, 0), limitX),
                                      y: min(max(desiredOrigin.y, 0), limitY)),
                       side: side)
    }

    /// 拖动某个角时保持不动的对角（图像坐标）。
    public func anchor(for corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: maxX, y: maxY)
        case .topRight:
            return CGPoint(x: minX, y: maxY)
        case .bottomLeft:
            return CGPoint(x: maxX, y: minY)
        case .bottomRight:
            return CGPoint(x: minX, y: minY)
        }
    }

    /// 以 `anchor` 为不动点，按鼠标位置生成新的正方形裁剪框。
    ///
    /// 边长取横纵两个方向位移的较大值，因此拖动角度不影响“正方形”这一约束。
    /// 返回 nil 表示这个方向已经没有余量，调用方应保持原状。
    public static func square(anchor: CGPoint, corner: CropCorner, mouse: CGPoint,
                              imageSize: CGSize,
                              minSide: CGFloat = CropBox.minimumSide) -> CropBox? {
        let candidate: CGFloat
        let maxSide: CGFloat
        switch corner {
        case .bottomRight:
            candidate = max(mouse.x - anchor.x, mouse.y - anchor.y)
            maxSide = min(imageSize.width - anchor.x, imageSize.height - anchor.y)
        case .topLeft:
            candidate = max(anchor.x - mouse.x, anchor.y - mouse.y)
            maxSide = min(anchor.x, anchor.y)
        case .topRight:
            candidate = max(mouse.x - anchor.x, anchor.y - mouse.y)
            maxSide = min(imageSize.width - anchor.x, anchor.y)
        case .bottomLeft:
            candidate = max(anchor.x - mouse.x, mouse.y - anchor.y)
            maxSide = min(anchor.x, imageSize.height - anchor.y)
        }
        guard maxSide > 1 else { return nil }

        let floor = Swift.min(minSide, maxSide)
        let side = min(max(candidate, floor), maxSide)
        let origin: CGPoint
        switch corner {
        case .bottomRight:
            origin = anchor
        case .topLeft:
            origin = CGPoint(x: anchor.x - side, y: anchor.y - side)
        case .topRight:
            origin = CGPoint(x: anchor.x, y: anchor.y - side)
        case .bottomLeft:
            origin = CGPoint(x: anchor.x - side, y: anchor.y)
        }
        return CropBox(origin: origin, side: side)
    }

    /// 导出用的整数裁剪区，含 Qt 版的取整与夹取顺序。
    public func integralCrop(imageSize: CGSize) -> IntegralCrop {
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)
        let side = max(1, min(Int((side).rounded()), width, height))
        let x = max(0, min(Int(origin.x.rounded()), width - side))
        let y = max(0, min(Int(origin.y.rounded()), height - side))
        return IntegralCrop(x: x, y: y, side: side)
    }
}

/// 整数像素裁剪区，图像坐标，原点在左上角。
public struct IntegralCrop: Equatable {
    public var x: Int
    public var y: Int
    public var side: Int

    public init(x: Int, y: Int, side: Int) {
        self.x = x
        self.y = y
        self.side = side
    }

    public var rect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(side), height: CGFloat(side))
    }
}
